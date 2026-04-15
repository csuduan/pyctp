#!/bin/bash
# pyctp 构建脚本
#
# 功能：
# 1. 编译 api 通过 cmake 和 make
# 2. 拷贝相关文件到 package 中
# 3. 为第三方实现库添加 RPATH
# 4. 在 package 中打包 wheel

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="${SCRIPT_DIR}/api"
PACKAGE_DIR="${SCRIPT_DIR}/package"
BUILD_DIR="${API_DIR}/build"

# 显示帮助信息
show_help() {
    echo "用法: $0 [linux|win32|win64|mac]"
    echo ""
    echo "选项:"
    echo "  linux   - 构建 Linux 版本 (默认)"
    echo "  win32   - 构建 Windows 32 位版本"
    echo "  win64   - 构建 Windows 64 位版本"
    echo "  mac     - 构建 macOS 版本"
    echo ""
    echo "示例:"
    echo "  $0 linux      # 构建 Linux 版本"
    echo "  $0 win64      # 构建 Windows 64 位版本"
}

# 检测平台
detect_platform() {
    local platform="$1"

    if [[ -z "$platform" ]]; then
        # 自动检测平台
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            platform="linux"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            platform="mac"
        elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
            # 检测架构
            arch=$(uname -m)
            if [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
                platform="win32"
            else
                platform="win64"
            fi
        else
            echo -e "${RED}错误: 无法自动检测平台${NC}"
            exit 1
        fi
    fi

    echo "$platform"
}

# 步骤 1: 编译 api
build_api() {
    local platform="$1"

    echo -e "${GREEN}[1/4] 编译 API (平台: $platform)...${NC}"

    cd "$API_DIR"

    # 创建并进入 build 目录
    if [[ -d "$BUILD_DIR" ]]; then
        echo "清理旧的构建目录..."
        rm -rf "$BUILD_DIR"
    fi
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # 运行 cmake
    echo "运行 cmake..."
    cmake ..

    # 编译
    echo "编译..."
    make

    echo -e "${GREEN}API 编译完成${NC}"
}

# 步骤 2: 拷贝构建产物和原生库到 package
copy_files() {
    local platform="$1"

    echo -e "${GREEN}[2/4] 拷贝构建产物到 package 目录...${NC}"

    # 重新创建 package/pyctp 下的实现子目录，并生成 __init__.py
    for impl_name in ctp rohon jees; do
        local package_impl_dir="${PACKAGE_DIR}/pyctp/${impl_name}"
        if [[ -d "$package_impl_dir" ]]; then
            rm -rf "$package_impl_dir"
        fi
        mkdir -p "$package_impl_dir"

        cat > "$package_impl_dir/__init__.py" << 'EOF'
from . import thostmduserapi as mdapi
from . import thosttraderapi as tdapi

__all__ = ['mdapi', 'tdapi']
EOF
    done

    # 遍历 build 目录下的所有实现子目录
    for impl_build_dir in "${BUILD_DIR}"/*/; do
        if [[ ! -d "$impl_build_dir" ]]; then
            continue
        fi

        local impl_name=$(basename "$impl_build_dir")
        # 跳过 CMake 内部目录
        if [[ "$impl_name" == "CMakeFiles" ]]; then
            continue
        fi
        local package_impl_dir="${PACKAGE_DIR}/pyctp/${impl_name}"
        local impl_libs_dir="${API_DIR}/libs/${impl_name}/${platform}"

        echo "  拷贝实现: ${impl_name}"
        mkdir -p "$package_impl_dir"

        # 拷贝 SWIG 构建产物 (.py, .so, .pyd)
        for file in "${impl_build_dir}"/*; do
            if [[ -f "$file" ]]; then
                local filename=$(basename "$file")
                case "$filename" in
                    thosttraderapi.py|thostmduserapi.py|_thosttraderapi.so|_thostmduserapi.so|_thosttraderapi.pyd|_thostmduserapi.pyd)
                        cp "$file" "$package_impl_dir/"
                        ;;
                esac
            fi
        done

        # 拷贝原生库文件
        if [[ -d "$impl_libs_dir" ]]; then
            for lib_file in "$impl_libs_dir"/*; do
                if [[ -f "$lib_file" ]]; then
                    local lib_name=$(basename "$lib_file")
                    case "$lib_name" in
                        *.so|*.dylib|*.dll|*.lib)
                            cp "$lib_file" "$package_impl_dir/"
                            ;;
                    esac
                fi
            done
        fi

        # Linux: 如果 so 文件的 SONAME 与文件名不同，创建符号链接
        if [[ "$platform" == "linux" ]]; then
            for so_file in "$package_impl_dir"/*.so; do
                if [[ -f "$so_file" ]]; then
                    local soname=$(readelf -d "$so_file" 2>/dev/null | grep SONAME | sed 's/.*\[//;s/\].*//')
                    local base_name=$(basename "$so_file")
                    if [[ -n "$soname" && "$soname" != "$base_name" && ! -f "$package_impl_dir/$soname" && ! -L "$package_impl_dir/$soname" ]]; then
                        echo "  创建符号链接: $soname -> $base_name"
                        ln -s "$base_name" "$package_impl_dir/$soname"
                    fi
                fi
            done
        fi

    done

    echo -e "${GREEN}拷贝完成${NC}"
}

# 步骤 3: 为各实现库添加 RPATH
fix_rpath() {
    local platform="$1"

    # 只有 Linux 平台需要设置 RPATH
    if [[ "$platform" != "linux" ]]; then
        echo -e "${YELLOW}[3/4] 跳过 RPATH 设置 (仅 Linux 需要)${NC}"
        return
    fi

    echo -e "${GREEN}[3/4] 为各实现库设置 RPATH...${NC}"

    # 检查 patchelf 是否存在
    if ! command -v patchelf &> /dev/null; then
        echo -e "${YELLOW}警告: patchelf 未安装，跳过 RPATH 设置${NC}"
        echo -e "${YELLOW}  安装命令: sudo apt install patchelf${NC}"
        return
    fi

    # 遍历所有实现目录
    for impl_dir in "${PACKAGE_DIR}/pyctp"/*/; do
        if [[ ! -d "$impl_dir" ]]; then
            continue
        fi

        local impl_name=$(basename "$impl_dir")
        if [[ "$impl_name" == "ctp" ]]; then
            # CTP 官方库通常不需要额外 RPATH 修复
            continue
        fi

        # 为该实现目录下的 API 库设置 RPATH
        for lib in libthosttraderapi_se.so libthostmduserapi_se.so; do
            local lib_path="${impl_dir}/${lib}"
            if [[ -f "$lib_path" ]]; then
                echo "  设置 ${impl_name}/${lib} 的 RPATH 为 \$ORIGIN..."
                patchelf --set-rpath '$ORIGIN' "$lib_path"
            fi
        done
    done

    echo -e "${GREEN}RPATH 设置完成${NC}"
}

# 步骤 4: 在 package 中打包 wheel
build_wheel() {
    echo -e "${GREEN}[4/4] 打包 wheel...${NC}"

    cd "$PACKAGE_DIR"

    # 清理旧的 dist 目录
    if [[ -d "dist" ]]; then
        rm -rf dist
    fi
    mkdir -p dist

    echo "执行 pip wheel . -w dist/"

    # 如果在 conda 环境中，使用 conda 的 pip
    if [[ -n "$CONDA_DEFAULT_ENV" ]] || [[ -n "$CONDA_PREFIX" ]]; then
        "$CONDA_PREFIX/bin/pip" wheel . -w dist/
    else
        pip wheel . -w dist/
    fi

    echo -e "${GREEN}wheel 打包完成，输出目录: ${PACKAGE_DIR}/dist${NC}"
}

# 主函数
main() {
    local platform
    platform=$(detect_platform "$1")

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  pyctp 构建脚本${NC}"
    echo -e "${GREEN}  平台: $platform${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # 检查依赖
    if ! command -v cmake &> /dev/null; then
        echo -e "${RED}错误: cmake 未安装${NC}"
        exit 1
    fi

    if ! command -v make &> /dev/null; then
        echo -e "${RED}错误: make 未安装${NC}"
        exit 1
    fi

    # 执行构建步骤
    build_api "$platform"
    copy_files "$platform"
    fix_rpath "$platform"
    build_wheel

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  构建完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 处理命令行参数
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

main "$@"

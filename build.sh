#!/bin/bash
# pyctp 构建脚本
#
# 功能：
# 1. 编译 api 通过 cmake 和 make
# 2. 拷贝相关文件到 src 中
# 3. 为第三方实现库添加 RPATH
# 4. 在 src 中打包 wheel

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="${SCRIPT_DIR}/api"
SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${API_DIR}/build"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项] [平台]"
    echo ""
    echo "平台选项:"
    echo "  linux   - 构建 Linux 版本 (默认)"
    echo "  win32   - 构建 Windows 32 位版本"
    echo "  win64   - 构建 Windows 64 位版本"
    echo "  mac     - 构建 macOS 版本"
    echo ""
    echo "其他选项:"
    echo "  --python VERSION  - 指定 Python 版本 (默认: 3.12)"
    echo "                      例如: --python 3.13"
    echo "  -h, --help        - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 mac                # 构建 macOS 版本，使用默认 Python 3.12"
    echo "  $0 --python 3.13 mac  # 构建 macOS 版本，使用 Python 3.13"
    echo "  $0 linux              # 构建 Linux 版本，使用默认 Python 3.12"
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

    # 重新创建 package/ctpx 下的实现子目录，并生成 __init__.py
    for impl_name in ctp rohon jees; do
        local package_impl_dir="${SRC_DIR}/ctpx/${impl_name}"
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
        local package_impl_dir="${SRC_DIR}/ctpx/${impl_name}"
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
    for impl_dir in "${SRC_DIR}/ctpx"/*/; do
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

# 步骤 4: 在项目根目录打包 wheel
build_wheel() {
    local platform="$1"
    local python_version="$2"

    echo -e "${GREEN}[4/4] 打包 wheel...${NC}"

    # pyproject.toml/setup.py 已移到项目根目录，必须从根目录构建
    cd "$SCRIPT_DIR"

    # 清理旧的 dist 目录
    if [[ -d "dist" ]]; then
        rm -rf dist
    fi
    mkdir -p dist

    # 确定使用的 Python 解释器
    local python_cmd="python"
    if [[ -n "$python_version" ]]; then
        local venv_dir=".venv${python_version//./}"
        # 检查虚拟环境是否存在
        if [[ ! -d "$venv_dir" ]]; then
            echo -e "${YELLOW}创建 Python ${python_version} 虚拟环境...${NC}"
            if command -v uv &> /dev/null; then
                uv venv --python "$python_version" "$venv_dir"
                uv pip install build setuptools wheel --python "$venv_dir/bin/python"
            else
                echo -e "${RED}错误: uv 未安装，无法创建指定 Python 版本的环境${NC}"
                echo -e "${YELLOW}请安装 uv: https://github.com/astral-sh/uv${NC}"
                exit 1
            fi
        fi
        python_cmd="$venv_dir/bin/python"
        echo "使用 Python ${python_version}: $python_cmd"
    else
        # 默认使用 Python 3.12
        python_version="3.12"
        local venv_dir=".venv312"
        if [[ ! -d "$venv_dir" ]]; then
            echo -e "${YELLOW}创建默认 Python 3.12 虚拟环境...${NC}"
            if command -v uv &> /dev/null; then
                uv venv --python 3.12 "$venv_dir"
                uv pip install build setuptools wheel --python "$venv_dir/bin/python"
            else
                echo -e "${RED}错误: uv 未安装，无法创建 Python 3.12 环境${NC}"
                echo -e "${YELLOW}请安装 uv: https://github.com/astral-sh/uv${NC}"
                exit 1
            fi
        fi
        python_cmd="$venv_dir/bin/python"
        echo "使用默认 Python 3.12: $python_cmd"
    fi

    # 使用 python -m build 构建 wheel
    # setup.py 中的 has_ext_modules=lambda: True 会自动检测平台标签
    echo "执行 $python_cmd -m build --wheel"
    "$python_cmd" -m build --wheel

    echo -e "${GREEN}wheel 打包完成，输出目录: ${SCRIPT_DIR}/dist${NC}"
    ls -lh dist/
}

# 主函数
main() {
    local platform=""
    local python_version=""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --python)
                python_version="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo -e "${RED}错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
            *)
                platform="$1"
                shift
                ;;
        esac
    done

    platform=$(detect_platform "$platform")

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  pyctp 构建脚本${NC}"
    echo -e "${GREEN}  平台: $platform${NC}"
    if [[ -n "$python_version" ]]; then
        echo -e "${GREEN}  Python: $python_version${NC}"
    else
        echo -e "${GREEN}  Python: 系统默认${NC}"
    fi
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
    build_wheel "$platform" "$python_version"

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

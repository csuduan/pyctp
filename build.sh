#!/bin/bash
# pyctp 构建脚本
#
# 功能：
# 1. 编译 api 通过 cmake 和 make
# 2. 拷贝相关文件到 package 中
# 3. 为融航的库添加 RPATH
# 4. 在 package 中执行打包和本地安装

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

# 步骤 2: 拷贝文件到 package（已由 cmake make 自动完成）
copy_files() {
    echo -e "${GREEN}[2/4] 文件已由 CMake 自动拷贝到 package 目录${NC}"
}

# 步骤 3: 为融航的库添加 RPATH
fix_rpath_rohon() {
    local platform="$1"

    # 只有 Linux 平台需要设置 RPATH
    if [[ "$platform" != "linux" ]]; then
        echo -e "${YELLOW}[3/4] 跳过 RPATH 设置 (仅 Linux 需要)${NC}"
        return
    fi

    echo -e "${GREEN}[3/4] 为融航库设置 RPATH...${NC}"

    # 检查 patchelf 是否存在
    if ! command -v patchelf &> /dev/null; then
        echo -e "${YELLOW}警告: patchelf 未安装，跳过 RPATH 设置${NC}"
        echo -e "${YELLOW}  安装命令: sudo apt install patchelf${NC}"
        return
    fi

    local rohon_lib_dir="${PACKAGE_DIR}/pyctp/lib/rohon"

    # 检查 rohon 目录是否存在
    if [[ ! -d "$rohon_lib_dir" ]]; then
        echo -e "${YELLOW}rohon 目录不存在，跳过 RPATH 设置${NC}"
        return
    fi

    # 为 rohon 的 API 库设置 RPATH
    for lib in libthosttraderapi_se.so libthostmduserapi_se.so; do
        local lib_path="${rohon_lib_dir}/${lib}"
        if [[ -f "$lib_path" ]]; then
            echo "  设置 ${lib} 的 RPATH 为 \$ORIGIN..."
            patchelf --set-rpath '$ORIGIN' "$lib_path"
        fi
    done

    echo -e "${GREEN}RPATH 设置完成${NC}"
}

# 步骤 4: 在 package 中执行打包和本地安装
install_package() {
    echo -e "${GREEN}[4/4] 安装包到本地环境...${NC}"

    cd "$PACKAGE_DIR"

    # 本地安装
    echo "执行 pip install -e ."

    # 如果在 conda 环境中，使用 conda 的 pip
    if [[ -n "$CONDA_DEFAULT_ENV" ]] || [[ -n "$CONDA_PREFIX" ]]; then
        # 在 conda 环境中
        "$CONDA_PREFIX/bin/pip" install -e .
    else
        # 使用系统的 pip
        pip install -e .
    fi

    echo -e "${GREEN}本地安装完成${NC}"
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
    copy_files
    fix_rpath_rohon "$platform"
    install_package

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

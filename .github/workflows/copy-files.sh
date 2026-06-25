#!/bin/bash
# 拷贝构建产物到 package 目录（用于 GitHub Actions）
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_DIR="${SCRIPT_DIR}/api"
PACKAGE_DIR="${SCRIPT_DIR}/package"
BUILD_DIR="${API_DIR}/build"
PLATFORM="${1:-mac}"

echo "[copy-files] 平台: $PLATFORM"

# 重新创建 package/ctpx 下的实现子目录，并生成 __init__.py
for impl_name in ctp rohon jees; do
    package_impl_dir="${PACKAGE_DIR}/ctpx/${impl_name}"
    if [[ -d "$package_impl_dir" ]]; then
        rm -rf "$package_impl_dir"
    fi
    mkdir -p "$package_impl_dir"

    cat > "$package_impl_dir/__init__.py" << 'PYEOF'
from . import thostmduserapi as mdapi
from . import thosttraderapi as tdapi

__all__ = ["mdapi", "tdapi"]
PYEOF
done

# 遍历 build 目录下的所有实现子目录
for impl_build_dir in "${BUILD_DIR}"/*/; do
    if [[ ! -d "$impl_build_dir" ]]; then
        continue
    fi

    impl_name=$(basename "$impl_build_dir")
    # 跳过 CMake 内部目录
    if [[ "$impl_name" == "CMakeFiles" ]]; then
        continue
    fi

    package_impl_dir="${PACKAGE_DIR}/ctpx/${impl_name}"
    impl_libs_dir="${API_DIR}/libs/${impl_name}/${PLATFORM}"

    echo "  拷贝实现: ${impl_name}"
    mkdir -p "$package_impl_dir"

    # 拷贝 SWIG 构建产物 (.py, .so, .pyd)
    for file in "${impl_build_dir}"/*; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
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
                lib_name=$(basename "$lib_file")
                case "$lib_name" in
                    *.so|*.dylib|*.dll|*.lib)
                        cp "$lib_file" "$package_impl_dir/"
                        ;;
                esac
            fi
        done
    fi

    # Linux: 如果 so 文件的 SONAME 与文件名不同，创建符号链接
    if [[ "$PLATFORM" == "linux" ]]; then
        for so_file in "$package_impl_dir"/*.so; do
            if [[ -f "$so_file" ]]; then
                soname=$(readelf -d "$so_file" 2>/dev/null | grep SONAME | sed 's/.*\[//;s/\].*//')
                base_name=$(basename "$so_file")
                if [[ -n "$soname" && "$soname" != "$base_name" && ! -f "$package_impl_dir/$soname" && ! -L "$package_impl_dir/$soname" ]]; then
                    echo "  创建符号链接: $soname -> $base_name"
                    ln -s "$base_name" "$package_impl_dir/$soname"
                fi
            fi
        done
    fi
done

echo "[copy-files] 拷贝完成"

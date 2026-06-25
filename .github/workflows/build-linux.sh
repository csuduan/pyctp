#!/bin/bash
# Linux manylinux 容器内构建脚本
set -e

echo "========================================"
echo "  ctpx Linux 构建脚本 (manylinux)"
echo "========================================"

# 安装构建依赖
echo "[1/5] 安装系统依赖..."
yum install -y cmake swig boost-devel patchelf python3-devel || \
dnf install -y cmake swig boost-devel patchelf python3-devel || \
(apt-get update && apt-get install -y cmake swig libboost-all-dev patchelf python3-dev)

# 安装 Python 构建工具
echo "[2/5] 安装 Python 构建工具..."
python3 -m pip install --upgrade pip setuptools wheel build auditwheel

# 编译 API
echo "[3/5] 编译 API..."
cd /workspace/api
mkdir -p build && cd build
cmake ..
make -j$(nproc)
cd /workspace

# 拷贝文件并设置 RPATH
echo "[4/5] 拷贝文件到 package..."
bash .github/workflows/copy-files.sh linux

# 设置 RPATH (Linux 需要 patchelf)
echo "[5/5] 设置 RPATH 并打包 wheel..."
if command -v patchelf &> /dev/null; then
    for impl_dir in /workspace/package/ctpx/*/; do
        if [[ ! -d "$impl_dir" ]]; then continue; fi
        impl_name=$(basename "$impl_dir")
        if [[ "$impl_name" == "ctp" ]]; then continue; fi
        for lib in libthosttraderapi_se.so libthostmduserapi_se.so; do
            lib_path="${impl_dir}/${lib}"
            if [[ -f "$lib_path" ]]; then
                echo "  设置 ${impl_name}/${lib} 的 RPATH 为 \$ORIGIN..."
                patchelf --set-rpath '$ORIGIN' "$lib_path"
            fi
        done
    done
else
    echo "  警告: patchelf 未安装，跳过 RPATH 设置"
fi

# 打包 wheel
cd /workspace/package
rm -rf dist
mkdir -p dist
pip wheel . -w dist/

# 使用 auditwheel 修复 wheel 标签
for whl in dist/*.whl; do
    if [[ -f "$whl" ]]; then
        auditwheel repair "$whl" --plat manylinux_2_28_x86_64 -w dist/
        rm -f "$whl"
    fi
done

echo "========================================"
echo "  Linux 构建完成！"
echo "  输出: /workspace/package/dist/"
echo "========================================"
ls -la /workspace/package/dist/

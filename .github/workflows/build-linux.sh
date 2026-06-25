#!/bin/bash
# Linux manylinux 容器内构建脚本
set -e

echo "========================================"
echo "  ctpx Linux 构建脚本 (manylinux)"
echo "========================================"

# 检测包管理器
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
else
    echo "错误: 未找到 dnf 或 yum"
    exit 1
fi

echo "[1/6] 使用包管理器: $PKG_MGR"

# 安装构建依赖
echo "[2/6] 安装系统依赖..."
$PKG_MGR install -y \
    cmake \
    swig \
    boost-devel \
    patchelf \
    python3-devel \
    gcc-c++ \
    make \
    glibc-devel

# 验证安装
echo "[3/6] 验证工具版本..."
cmake --version
swig -version
python3 --version

# 安装 Python 构建工具
echo "[4/6] 安装 Python 构建工具..."
python3 -m pip install --upgrade pip setuptools wheel build auditwheel

# 编译 API
echo "[5/6] 编译 API..."
cd /workspace/api
rm -rf build
mkdir -p build && cd build
cmake .. || {
    echo "CMake 配置失败，查看错误日志..."
    cat CMakeFiles/CMakeError.log 2>/dev/null || true
    cat CMakeFiles/CMakeOutput.log 2>/dev/null || true
    exit 1
}
make -j$(nproc) || {
    echo "Make 编译失败"
    exit 1
}
cd /workspace

# 拷贝文件并设置 RPATH
echo "[6/6] 拷贝文件到 package..."
bash .github/workflows/copy-files.sh linux

# 设置 RPATH (Linux 需要 patchelf)
echo "设置 RPATH..."
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
echo "打包 wheel..."
cd /workspace/package
rm -rf dist
mkdir -p dist
pip wheel . -w dist/ || {
    echo "pip wheel 打包失败"
    exit 1
}

# 使用 auditwheel 修复 wheel 标签
for whl in dist/*.whl; do
    if [[ -f "$whl" ]]; then
        echo "修复 wheel: $(basename $whl)"
        auditwheel repair "$whl" --plat manylinux_2_28_x86_64 -w dist/ || {
            echo "auditwheel 修复失败，尝试直接保留原文件..."
            continue
        }
        rm -f "$whl"
    fi
done

echo "========================================"
echo "  Linux 构建完成！"
echo "  输出: /workspace/package/dist/"
echo "========================================"
ls -la /workspace/package/dist/

#!/bin/bash
# pyctp 构建脚本（scikit-build-core 版本）
#
# scikit-build-core 会直接调用 CMake 构建 SWIG 扩展，
# 并将产物安装到 wheel 中。本脚本仅做清理和触发构建。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 创建 uv 虚拟环境（已存在则跳过）
if [ ! -d ".venv" ]; then
    uv venv --python 3.12
fi
source .venv/bin/activate

# 安装构建依赖
uv pip install build scikit-build-core

# 清理旧的构建产物
rm -rf dist build _skbuild src/*.egg-info *.egg-info

# 构建 wheel
python -m build --wheel

# 列出结果
echo ""
echo "构建完成，输出目录: ${SCRIPT_DIR}/dist"
ls -lh dist/

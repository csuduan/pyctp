# ctpx

本项目使用 SWIG 将 CTP C++ 接口封装为 Python 接口，支持官方 CTP 库或三方兼容库（如融航、杰宜斯等）。





## 构建
### 依赖

若从源码构建，需要安装以下工具：

- Python >= 3.12
- SWIG
- Boost
- CMake

### macOS

```bash
brew install swig boost cmake
```

### Linux

```bash
sudo apt install swig libboost-all-dev cmake
```

### 编译及打包

项目使用 [scikit-build-core](https://scikit-build-core.readthedocs.io/) 作为构建后端，构建时会自动调用 CMake 编译 SWIG 扩展并打包成 wheel。

```bash
./build.sh
或者
uv build
```

### Linux manylinux 发布版

发布到 PyPI 的 Linux wheel 需要在 manylinux 容器中构建并使用 `auditwheel repair`。本项目通过 `cibuildwheel` 在 GitHub Actions 中完成这一流程，详见 `.github/workflows/build-release.yml`。




## 使用

* 安装 wheel

```bash
pip install dist/*.whl
#或者
pip install ctpx

```

* 官方 CTP 实现

```python
from ctpx.ctp import mdapi, tdapi

trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

* 融航实现

```python
from ctpx.rohon import mdapi, tdapi

trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

## 注意事项

1. **同一进程只能使用一种实现**：不可同时导入 `ctpx.ctp` 和 `ctpx.rohon`。
2. **Windows DLL 搜索**：Python 3.8+ 使用 `os.add_dll_directory`，旧版本需要设置 `PATH`。
3. **Linux 预加载**：使用 `ctypes.CDLL(..., RTLD_GLOBAL)` 确保符号全局可见。

## 参考

- openctp
- vnpy_ctp
- [CTPAPI-Python 开发攻略](https://zhuanlan.zhihu.com/p/688672132)

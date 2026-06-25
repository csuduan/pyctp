# ctpx

本项目使用 SWIG 将 CTP C++ 接口封装为 Python 接口，支持官方 CTP 库或三方兼容库（如融航、杰宜斯等）。

## 安装

```bash
pip install ctpx
```

## 依赖

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

### Windows

【待测试】

## 编译

```bash
./build.sh
```

构建完成后，wheel 位于 `dist/`。

## 安装本地 wheel

```bash
pip install dist/*.whl
```


## 使用方法

### 官方 CTP 实现

```python
from ctpx.ctp import mdapi, tdapi

trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

### 融航实现

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

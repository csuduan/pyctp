# ctx - ctp的python封装

本项目通过 SWIG 封装 CTP C++ 接口，支持官方 CTP 库或三方兼容库（如融航、杰宜斯等）。

## 特性

- **多平台支持**: Linux / macOS / Win64
- **支持兼容接口**：融航、杰宜斯等
- **子包导入**: 通过 `from ctpx.ctp import mdapi, tdapi` 优雅选择实现


## 安装

```bash
pip install ctx
```

## 使用方法

### 官方 CTP 实现

```python
from ctpx.ctp import mdapi, tdapi

# 创建交易API实例
trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()

# 创建行情API实例
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

### 融航实现

```python
from ctpx.rohon import mdapi, tdapi

# 创建交易API实例
trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()

# 创建行情API实例
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

## 注意事项

1. **同一进程只能使用一种实现**：不可同时导入 `ctpx.ctp` 和 `ctpx.rohon`
2. **Windows DLL 搜索**：Python 3.8+ 使用 `os.add_dll_directory`，旧版本需要设置 PATH
3. **Linux 预加载**：使用 `ctypes.CDLL(..., RTLD_GLOBAL)` 确保符号全局可见

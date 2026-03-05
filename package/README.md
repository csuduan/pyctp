# CTP Python API - 多平台多实现支持

本项目通过 SWIG 封装 CTP C++ 接口，支持官方 CTP 库或三方兼容库（如融航）。

## 特性

- **多平台支持**: Linux / macOS / Windows 32位 / Windows 64位
- **子包导入**: 通过 `from pyctp.ctp import mdapi, tdapi` 优雅选择实现
- **自动加载**: 导入时自动处理库路径和依赖

## 项目结构

```
package/pyctp/
├── __init__.py              # 包初始化，导出 ctp/rohon 子包
├── _loader.py               # 动态库加载核心逻辑
├── ctp/                     # 官方 CTP 子包
│   └── __init__.py          # 导入时自动加载 CTP 库
├── rohon/                   # 融航兼容子包
│   └── __init__.py          # 导入时自动加载融航库
├── thostmduserapi.py        # SWIG 生成的行情 API
├── thosttraderapi.py        # SWIG 生成的交易 API
├── lib/                     # 库文件目录
│   ├── ctp/                 # 官方 CTP 库
│   └── rohon/               # 融航兼容库
└── ...
```

## 安装

### 1. 编译项目

```bash
cd api
mkdir build && cd build
cmake ..
make
```

### 2. 收集库文件

```bash
# 使用提供的构建脚本
cd ../..
./build.sh linux    # Linux
./build.sh win64    # Windows 64位

# 或手动复制文件：
# - SWIG 生成的 _thost*.so/.pyd -> package/pyctp/
# - 官方库 -> package/pyctp/lib/ctp/
# - 融航库 -> package/pyctp/lib/rohon/
```

### 3. 安装包

```bash
cd package
pip install .
```

## 使用方法

### 官方 CTP 实现

```python
from pyctp.ctp import mdapi, tdapi

# 创建交易API实例
trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()

# 创建行情API实例
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

### 融航实现

```python
from pyctp.rohon import mdapi, tdapi

# 创建交易API实例
trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()

# 创建行情API实例
md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
```

## API 参考

### `pyctp.ctp.mdapi`

官方 CTP 行情 API 模块。用法与原生 CTP C++ API 一致。

### `pyctp.ctp.tdapi`

官方 CTP 交易 API 模块。用法与原生 CTP C++ API 一致。

### `pyctp.rohon.mdapi`

融航兼容行情 API 模块。

### `pyctp.rohon.tdapi`

融航兼容交易 API 模块。

### 工具函数

```python
import pyctp

# 获取可用的实现列表
pyctp.get_available_implementations()  # 返回 ['ctp', 'rohon']

# 获取当前加载的实现名称
pyctp.get_current_implementation()     # 返回 'ctp' 或 'rohon'

# 获取库实现目录路径
pyctp.get_impl_dir('ctp')              # 返回 Path 对象
```

## 支持的库实现

| 实现名称 | 说明 | 需要的库文件 |
|---------|------|------------|
| ctp | 官方 CTP 库 | libthosttraderapi_se.so, libthostmduserapi_se.so |
| rohon | 融航兼容库 | libthosttraderapi_se.so, librohonbase.so, libLinuxDataCollect.so |

## 注意事项

1. **同一进程只能使用一种实现**：不可同时导入 `pyctp.ctp` 和 `pyctp.rohon`
2. **库依赖顺序**：融航的库有依赖关系，`_loader.py` 会自动按正确顺序加载
3. **Windows DLL 搜索**：Python 3.8+ 使用 `os.add_dll_directory`，旧版本需要设置 PATH
4. **Linux 预加载**：使用 `ctypes.CDLL(..., RTLD_GLOBAL)` 确保符号全局可见

## 打包分发

### Linux 包

```bash
cd package
# 确保 lib/ctp/ 和 lib/rohon/ 包含 Linux 库文件
pip wheel . -w dist/
```

### Windows 32位 包

```bash
# 在 Windows 32位环境编译后
cd package
# 确保 lib/ctp/ 和 lib/rohon/ 包含 Win32 库文件
pip wheel . -w dist/
```

### Windows 64位 包

```bash
# 在 Windows 64位环境编译后
cd package
# 确保 lib/ctp/ 和 lib/rohon/ 包含 Win64 库文件
pip wheel . -w dist/
```

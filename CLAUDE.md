# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Python wrapper for the CTP (China Futures Trading Platform) C++ API using SWIG. It enables Python applications to connect to Chinese futures exchanges through the official CTP protocol.

## Build Commands

### Prerequisites
- cmake, swig, boost (with locale library)
- Python 3.8+
- Visual Studio (Windows) or gcc/clang (Linux)

### Environment Variables (if not using system packages)
```bash
# Linux/macOS
export PYTHON_INCLUDE=/path/to/python/include
export PYTHON_LIB=/path/to/python/lib

# Windows
set BOOST_INCLUDE=E:\boost_1_73_0
set BOOST_LIB=E:\boost_1_73_0\stage\lib
set PYTHON_INCLUDE=C:\Program Files\Python312\include
set PYTHON_LIB=C:\Program Files\Python312\libs
```

### Build
```bash
# Using the build script (recommended)
./build.sh linux      # Linux build
./build.sh win32      # Windows 32-bit
./build.sh win64      # Windows 64-bit

# Manual CMake build (Linux example)
cd api
mkdir build && cd build
cmake ..
make
```

### Package Installation
```bash
cd package
pip install .

# Create wheel package
pip wheel . -w dist/
```

## Architecture

### Directory Structure
```
├── api/                    # C++ API wrapper source
│   ├── CMakeLists.txt      # CMake build configuration
│   ├── includes/           # CTP header files from upstream
│   ├── libs/               # Pre-compiled native libraries
│   │   ├── ctp/            # Official CTP libraries (linux, mac, win64)
│   │   └── rohon/          # Rohon compatible libraries
│   ├── thostmduserapi.i    # SWIG interface (market data)
│   └── thosttraderapi.i    # SWIG interface (trading)
├── demo/                   # Example usage code
├── package/pyctp/          # Python package for distribution
│   ├── __init__.py         # Package entry point with load() function
│   ├── _loader.py          # Dynamic library loader
│   ├── config.py           # Default implementation config
│   └── lib/                # Library files populated at build
└── build.sh                # Cross-platform build script
```

### Dynamic Implementation Switching

The package supports runtime switching between different CTP implementations:

```python
import pyctp

# Load official CTP
pyctp.load('ctp')
from pyctp import mdapi, tdapi

# Or load Rohon (融航) compatible implementation
pyctp.load('rohon')
from pyctp import mdapi, tdapi
```

Implementation loading flow (`package/pyctp/_loader.py`):
1. `load()` sets up library paths via `setup_library_path()`
2. On Linux: preloads dependencies with `RTLD_GLOBAL` in dependency order
3. On Windows: adds DLL directory via `os.add_dll_directory()` or PATH
4. Imports SWIG-generated modules which then load the native libraries

The `_loader.py` defines `IMPLEMENTATIONS` dict mapping implementation names to platform-specific library configurations including dependency loading order.

### Build Flow

1. SWIG generates Python wrappers and C++ binding code from `.i` interface files
2. CMake compiles the C++ bindings into shared modules (`_thostmduserapi.so`, `_thosttraderapi.so`)
3. Build script copies generated files + native libraries to `package/pyctp/`
4. pip installs the complete package

### Key Components

- **mdapi** (`thostmduserapi`): Market data API (行情API) - receives price quotes
- **tdapi** (`thosttraderapi`): Trading API (交易API) - sends orders, queries positions

Both APIs use async callback patterns via SPI classes that must be subclassed.

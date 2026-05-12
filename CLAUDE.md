# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Python wrapper for the CTP (China Futures Trading Platform) C++ API using SWIG. It enables Python applications to connect to Chinese futures exchanges through the official CTP protocol.

The package supports multiple CTP-compatible implementations:
- **ctp**: Official CTP libraries
- **rohon**: Rohon (融航) compatible libraries
- **jees**: Jees compatible libraries

Each implementation uses its own header files and native libraries, allowing different API versions to coexist in the same package.

## Build Commands

### Prerequisites
- cmake, swig, boost (with locale library)
- Python 3.8+
- Visual Studio (Windows) or gcc/clang (Linux/macOS)

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
./build.sh mac        # macOS build
```

The build script performs the following steps:
1. Compiles SWIG bindings via CMake (one per implementation)
2. Copies build artifacts and native libraries to `package/pyctp/<impl>/`
3. Fixes RPATH on Linux for third-party implementations
4. Builds a wheel package in `package/dist/`

### Manual CMake Build (for debugging)
```bash
cd api
mkdir build && cd build
cmake ..
make
```
CMake only compiles the bindings; it does **not** copy files to `package/`.

## Architecture

### Directory Structure
```
├── api/                         # C++ API wrapper source
│   ├── CMakeLists.txt           # CMake build configuration
│   ├── libs/                    # Pre-compiled native libraries
│   │   ├── ctp/
│   │   │   ├── linux/
│   │   │   │   ├── include/     # Platform-specific headers
│   │   │   │   └── *.so
│   │   │   ├── mac/
│   │   │   │   ├── include/
│   │   │   │   └── *.dylib
│   │   │   └── win64/
│   │   │       ├── include/
│   │   │       └── *.dll
│   │   ├── rohon/               # Rohon compatible libraries
│   │   └── jees/                # Jees compatible libraries
│   ├── thostmduserapi.i         # SWIG interface (market data)
│   └── thosttraderapi.i         # SWIG interface (trading)
├── demo/                        # Example usage code
├── package/pyctp/               # Python package for distribution
│   ├── __init__.py              # Package entry point
│   ├── ctp/                     # CTP implementation (generated at build)
│   ├── rohon/                   # Rohon implementation (generated at build)
│   └── jees/                    # Jees implementation (generated at build)
├── package/pyproject.toml       # Package configuration
└── build.sh                     # Cross-platform build script
```

### Implementation Subpackages

Each implementation is an isolated Python subpackage containing its own SWIG-generated bindings:

```python
# Use official CTP
from pyctp.ctp import mdapi, tdapi

# Use Rohon
from pyctp.rohon import mdapi, tdapi

# Use Jees
from pyctp.jees import mdapi, tdapi
```

**Note:** Only one implementation can be imported per Python process because the underlying C++ libraries export conflicting symbols.

### Build Flow

1. CMake generates and compiles separate SWIG bindings for each implementation into `api/build/<impl>/`
2. `build.sh` copies the generated `.py`/`.so` (or `.pyd`) files plus native libraries to `package/pyctp/<impl>/`
3. `build.sh` generates `__init__.py` in each implementation directory
4. On Linux, `build.sh` may create symlinks if a `.so` file's SONAME differs from its filename (e.g., `thosttraderapi_se_6.7.2.so -> libthosttraderapi_se.so`)
5. `build.sh` builds the wheel package via `pip wheel . -w dist/`

### Key Components

- **mdapi** (`thostmduserapi`): Market data API (行情API) - receives price quotes
- **tdapi** (`thosttraderapi`): Trading API (交易API) - sends orders, queries positions

Both APIs use async callback patterns via SPI classes that must be subclassed.

### Version Control

Only `package/pyctp/__init__.py` is tracked in git. The implementation directories (`ctp/`, `rohon/`, `jees/`) and all generated library files are ignored because they are produced by `build.sh`.

"""
动态库加载模块 - 支持多平台库实现

支持官方CTP库和三方兼容库（如融航）的库路径设置
"""

import os
import sys
import ctypes
from pathlib import Path

# 支持的库实现配置
# 定义每个平台需要的库文件列表（按依赖顺序）
IMPLEMENTATIONS = {
    'ctp': {
        'linux': {
            'libs': ['libthosttraderapi_se.so', 'libthostmduserapi_se.so'],
            'priority': ['libthosttraderapi_se.so', 'libthostmduserapi_se.so']
        },
        'darwin': {
            'libs': ['libthosttraderapi_se.dylib', 'libthostmduserapi_se.dylib'],
            'priority': ['libthosttraderapi_se.dylib', 'libthostmduserapi_se.dylib']
        },
        'win32': {
            'libs': ['thosttraderapi_se.dll', 'thostmduserapi_se.dll'],
            'priority': ['thosttraderapi_se.dll', 'thostmduserapi_se.dll']
        },
        'win64': {
            'libs': ['thosttraderapi_se.dll', 'thostmduserapi_se.dll'],
            'priority': ['thosttraderapi_se.dll', 'thostmduserapi_se.dll']
        },
    },
    'rohon': {
        'linux': {
            'libs': [
                'libthosttraderapi_se.so',
                'libthostmduserapi_se.so',
                'librohonbase.so',
                'libLinuxDataCollect.so'
            ],
            # 按依赖顺序：先加载基础库，再加载接口库
            'priority': [
                'libLinuxDataCollect.so',
                'librohonbase.so',
                'libthosttraderapi_se.so',
                'libthostmduserapi_se.so'
            ]
        },
        'win32': {
            'libs': [
                'thosttraderapi_se.dll',
                'thostmduserapi_se.dll',
                'rohonbase.dll'
            ],
            'priority': [
                'rohonbase.dll',
                'thosttraderapi_se.dll',
                'thostmduserapi_se.dll'
            ]
        },
        'win64': {
            'libs': [
                'thosttraderapi_se.dll',
                'thostmduserapi_se.dll',
                'rohonbase.dll'
            ],
            'priority': [
                'rohonbase.dll',
                'thosttraderapi_se.dll',
                'thostmduserapi_se.dll'
            ]
        },
    }
}

# 当前加载的实现
_current_impl = None

# Windows DLL 路径记录（避免重复添加）
_windows_dll_paths = set()


def get_platform():
    """
    获取当前平台标识

    Returns:
        str: 'linux', 'darwin', 'win32', 或 'win64'
    """
    if sys.platform.startswith('linux'):
        return 'linux'
    elif sys.platform == 'win32':
        import platform
        arch = platform.architecture()[0]
        return 'win32' if arch == '32bit' else 'win64'
    elif sys.platform == 'darwin':
        return 'darwin'
    else:
        raise RuntimeError(f"Unsupported platform: {sys.platform}")


def get_impl_dir(impl_name='ctp'):
    """
    获取库实现目录路径

    Args:
        impl_name: 库实现名称，如 'ctp', 'rohon'

    Returns:
        Path: 库实现目录的路径
    """
    pkg_dir = Path(__file__).parent
    return pkg_dir / 'lib' / impl_name


def get_available_implementations():
    """
    获取可用的库实现列表

    Returns:
        list: 可用的实现名称列表
    """
    pkg_dir = Path(__file__).parent
    lib_dir = pkg_dir / 'lib'
    if not lib_dir.exists():
        return []
    return [d.name for d in lib_dir.iterdir() if d.is_dir()]


def get_current_implementation():
    """
    获取当前加载的实现名称

    Returns:
        str: 当前实现名称，或 None
    """
    return _current_impl


def _preload_libs(impl_dir, lib_names):
    """
    使用 ctypes 预加载动态库 (Linux/macOS)

    Args:
        impl_dir: 库文件目录
        lib_names: 库文件名列表（按依赖顺序）
    """
    for lib_name in lib_names:
        lib_path = impl_dir / lib_name
        if lib_path.exists():
            try:
                # RTLD_GLOBAL 确保符号对其他库可见
                ctypes.CDLL(str(lib_path), ctypes.RTLD_GLOBAL)
            except OSError as e:
                print(f"Warning: Failed to preload {lib_name}: {e}")


def _setup_windows_dll_path(impl_dir):
    """
    Windows: 设置 DLL 搜索路径

    Args:
        impl_dir: 库文件目录
    """
    impl_dir_str = str(impl_dir)

    # Python 3.8+: 使用 add_dll_directory
    if hasattr(os, 'add_dll_directory'):
        # 检查是否已添加
        if impl_dir_str not in _windows_dll_paths:
            os.add_dll_directory(impl_dir_str)
            _windows_dll_paths.add(impl_dir_str)
    else:
        # 旧版本：修改 PATH 环境变量
        paths = os.environ.get('PATH', '').split(os.pathsep)
        if impl_dir_str not in paths:
            os.environ['PATH'] = impl_dir_str + os.pathsep + os.environ.get('PATH', '')


def setup_library_path(impl_name='ctp'):
    """
    设置库加载路径并预加载依赖库

    此函数在子包导入时自动调用，用户通常不需要直接调用。

    Args:
        impl_name: 库实现名称，如 'ctp' 或 'rohon'

    Raises:
        RuntimeError: 如果指定的实现不存在
    """
    global _current_impl

    platform = get_platform()
    impl_dir = get_impl_dir(impl_name)

    if not impl_dir.exists():
        available = get_available_implementations()
        raise RuntimeError(
            f"Implementation '{impl_name}' not found at {impl_dir}. "
            f"Available implementations: {available}"
        )

    # 获取该实现的库配置
    impl_config = IMPLEMENTATIONS.get(impl_name, {}).get(platform, {})
    lib_priority = impl_config.get('priority', impl_config.get('libs', []))

    if platform in ('win32', 'win64'):
        _setup_windows_dll_path(impl_dir)
    else:
        # Linux/macOS: 预加载依赖库
        _preload_libs(impl_dir, lib_priority)

    _current_impl = impl_name

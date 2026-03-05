"""
CTP (China Futures Market) Python API Wrapper

支持多平台库实现：
- 官方 CTP 库
- 三方兼容库（如融航）

使用方法：
    # 使用官方CTP实现
    from pyctp.ctp import mdapi, tdapi

    # 使用融航实现
    from pyctp.rohon import mdapi, tdapi

注意：同一进程中只能使用一种实现，不可同时导入 ctp 和 rohon。
"""

__version__ = '6.7.2'
__author__ = 'duanqing'

# 导出工具函数
from ._loader import (
    get_impl_dir,
    get_available_implementations,
    get_current_implementation,
)

__all__ = [
    'get_impl_dir',
    'get_available_implementations',
    'get_current_implementation',
]
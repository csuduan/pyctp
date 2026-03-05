"""
官方 CTP 库实现

使用方法:
    from pyctp.ctp import mdapi, tdapi

    # 创建交易API实例
    trader_api = tdapi.CThostFtdcTraderApi.CreateFtdcTraderApi()

    # 创建行情API实例
    md_api = mdapi.CThostFtdcMdApi.CreateFtdcMdApi()
"""

# 先设置CTP库路径
from .._loader import setup_library_path
setup_library_path('ctp')

# 导入SWIG生成的模块
from .. import thostmduserapi as mdapi
from .. import thosttraderapi as tdapi

__all__ = ['mdapi', 'tdapi']

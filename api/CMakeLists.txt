cmake_minimum_required(VERSION 3.10)

project(pyctp)

set(CMAKE_CXX_STANDARD 11)

# -----------------------------------------------------------------------------
# 平台检测
# -----------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(CTP_PLATFORM "linux")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    if(CMAKE_GENERATOR_PLATFORM STREQUAL "x86" OR CMAKE_SIZEOF_VOID_P EQUAL 4)
        set(CTP_PLATFORM "win32")
    else()
        set(CTP_PLATFORM "win64")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(CTP_PLATFORM "mac")
else()
    message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_NAME}")
endif()

message(STATUS "CTP Platform: ${CTP_PLATFORM}")

# -----------------------------------------------------------------------------
# 设置头文件和库路径
# -----------------------------------------------------------------------------
# 头文件路径（使用对应平台的头文件）
set(CTP_INCLUDES_DIR ${PROJECT_SOURCE_DIR}/libs/ctp/${CTP_PLATFORM})

# 构建时使用 CTP 官方库（接口定义一致）
set(CTP_BUILD_LIBS_DIR ${PROJECT_SOURCE_DIR}/libs/ctp/${CTP_PLATFORM})

# 检查库目录是否存在
if(NOT EXISTS ${CTP_BUILD_LIBS_DIR})
    message(FATAL_ERROR "CTP library directory not found: ${CTP_BUILD_LIBS_DIR}")
endif()

# 查找 Python
find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
message(STATUS "Python3 found: ${Python3_EXECUTABLE}")
message(STATUS "Python3 include: ${Python3_INCLUDE_DIRS}")
message(STATUS "Python3 library: ${Python3_LIBRARIES}")

# 查找 Boost
if(DEFINED ENV{BOOST_INCLUDE})
    set(BOOST_INCLUDE_DIRS $ENV{BOOST_INCLUDE})
    set(BOOST_LIB_DIRS $ENV{BOOST_LIB})
    message(STATUS "Using Boost from environment: ${BOOST_INCLUDE_DIRS}")
else()
    # 尝试找到 Boost (只需要头文件)
    find_package(Boost REQUIRED)
    if(Boost_FOUND)
        set(BOOST_INCLUDE_DIRS ${Boost_INCLUDE_DIRS})
        set(BOOST_LIB_DIRS ${Boost_LIBRARY_DIRS})
        message(STATUS "Boost found: ${Boost_VERSION}")
        message(STATUS "Boost include: ${Boost_INCLUDE_DIRS}")
    endif()
endif()

# 设置头文件搜索路径
include_directories(
    ${CTP_INCLUDES_DIR}
    ${Python3_INCLUDE_DIRS}
    ${BOOST_INCLUDE_DIRS}
)

# 设置库搜索路径
link_directories(
    ${CTP_BUILD_LIBS_DIR}
    ${Python3_LIBRARY_DIRS}
    ${BOOST_LIB_DIRS}
)

# -----------------------------------------------------------------------------
# 平台特定编译选项
# -----------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    add_compile_options(/bigobj /MT)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # Linux 使用 -fPIC 生成位置无关代码
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # macOS 特定选项
    set(CMAKE_MACOSX_RPATH ON)
endif()

# -----------------------------------------------------------------------------
# 生成 SWIG 包装代码
# -----------------------------------------------------------------------------
set(TD_API _thosttraderapi)
set(MD_API _thostmduserapi)

message(STATUS "Generating SWIG wrapper files...")

# 查找 SWIG
find_program(SWIG_EXECUTABLE swig)
if(NOT SWIG_EXECUTABLE)
    message(FATAL_ERROR "SWIG not found. Please install SWIG.")
endif()

# 定义生成的文件路径
set(TD_WRAPPER_CXX ${CMAKE_CURRENT_BINARY_DIR}/thosttraderapi_wrap.cxx)
set(TD_WRAPPER_PY ${CMAKE_CURRENT_BINARY_DIR}/thosttraderapi.py)
set(MD_WRAPPER_CXX ${CMAKE_CURRENT_BINARY_DIR}/thostmduserapi_wrap.cxx)
set(MD_WRAPPER_PY ${CMAKE_CURRENT_BINARY_DIR}/thostmduserapi.py)

# 生成交易 API 包装代码
add_custom_command(
    OUTPUT ${TD_WRAPPER_CXX} ${TD_WRAPPER_PY}
    COMMAND ${SWIG_EXECUTABLE} -threads -c++ -python
        -outdir ${CMAKE_CURRENT_BINARY_DIR}
        -o ${TD_WRAPPER_CXX}
        -I${CTP_INCLUDES_DIR}
        ${PROJECT_SOURCE_DIR}/thosttraderapi.i
    DEPENDS ${PROJECT_SOURCE_DIR}/thosttraderapi.i
        ${CTP_INCLUDES_DIR}/ThostFtdcTraderApi.h
        ${CTP_INCLUDES_DIR}/ThostFtdcUserApiDataType.h
        ${CTP_INCLUDES_DIR}/ThostFtdcUserApiStruct.h
    COMMENT "Generating SWIG wrapper for thosttraderapi"
)

# 生成行情 API 包装代码
add_custom_command(
    OUTPUT ${MD_WRAPPER_CXX} ${MD_WRAPPER_PY}
    COMMAND ${SWIG_EXECUTABLE} -threads -c++ -python
        -outdir ${CMAKE_CURRENT_BINARY_DIR}
        -o ${MD_WRAPPER_CXX}
        -I${CTP_INCLUDES_DIR}
        ${PROJECT_SOURCE_DIR}/thostmduserapi.i
    DEPENDS ${PROJECT_SOURCE_DIR}/thostmduserapi.i
        ${CTP_INCLUDES_DIR}/ThostFtdcMdApi.h
        ${CTP_INCLUDES_DIR}/ThostFtdcUserApiDataType.h
        ${CTP_INCLUDES_DIR}/ThostFtdcUserApiStruct.h
    COMMENT "Generating SWIG wrapper for thostmduserapi"
)

# 创建自定义目标确保 SWIG 文件被生成
add_custom_target(swig_wrappers ALL
    DEPENDS ${TD_WRAPPER_CXX} ${MD_WRAPPER_CXX}
)

# -----------------------------------------------------------------------------
# 编译交易 API 模块
# -----------------------------------------------------------------------------
add_library(${TD_API} SHARED ${TD_WRAPPER_CXX})

add_dependencies(${TD_API} swig_wrappers)

set_target_properties(${TD_API} PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set_target_properties(${TD_API} PROPERTIES
        PREFIX ""                              # 去掉 lib 前缀
        SUFFIX ".so"
        BUILD_RPATH "$ORIGIN/lib/ctp:$ORIGIN/lib/rohon"
        INSTALL_RPATH "$ORIGIN/lib/ctp:$ORIGIN/lib/rohon"
    )
    target_link_libraries(${TD_API}
        ${CTP_BUILD_LIBS_DIR}/libthosttraderapi_se.so
    )
    # Boost 库链接
    if(BOOST_LIB_DIRS)
        target_link_libraries(${TD_API}
            ${BOOST_LIB_DIRS}/libboost_locale.so
            ${BOOST_LIB_DIRS}/libboost_system.so
        )
    else()
        find_library(BOOST_LOCALE_LIB boost_locale)
        find_library(BOOST_SYSTEM_LIB boost_system)
        if(BOOST_LOCALE_LIB)
            target_link_libraries(${TD_API} ${BOOST_LOCALE_LIB})
        else()
            target_link_libraries(${TD_API} boost_locale)
        endif()
        if(BOOST_SYSTEM_LIB)
            target_link_libraries(${TD_API} ${BOOST_SYSTEM_LIB})
        else()
            target_link_libraries(${TD_API} boost_system)
        endif()
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set_target_properties(${TD_API} PROPERTIES
        PREFIX ""
        SUFFIX ".pyd"
    )
    target_link_libraries(${TD_API}
        thosttraderapi_se.lib
    )
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set_target_properties(${TD_API} PROPERTIES
        PREFIX ""
        SUFFIX ".so"
        MACOSX_RPATH ON
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "@loader_path;@loader_path/lib/ctp"
    )
    # macOS: 添加 -undefined dynamic_lookup 以允许运行时解析 Python 符号
    target_link_options(${TD_API} PRIVATE "LINKER:-undefined,dynamic_lookup")
    # macOS: 使用 dylib 格式库
    target_link_libraries(${TD_API}
        ${CTP_BUILD_LIBS_DIR}/libthosttraderapi_se.dylib
    )
    # 如果找到 Boost，链接 Boost 库
    if(Boost_FOUND)
        find_library(BOOST_LOCALE_LIB boost_locale PATHS ${BOOST_LIB_DIRS} /opt/homebrew/lib)
        if(BOOST_LOCALE_LIB)
            target_link_libraries(${TD_API} ${BOOST_LOCALE_LIB})
        else()
            target_link_libraries(${TD_API} boost_locale)
        endif()
    endif()
endif()

# -----------------------------------------------------------------------------
# 编译行情 API 模块
# -----------------------------------------------------------------------------
add_library(${MD_API} SHARED ${MD_WRAPPER_CXX})

add_dependencies(${MD_API} swig_wrappers)

set_target_properties(${MD_API} PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set_target_properties(${MD_API} PROPERTIES
        PREFIX ""                              # 去掉 lib 前缀
        SUFFIX ".so"
        BUILD_RPATH "$ORIGIN/lib/ctp:$ORIGIN/lib/rohon"
        INSTALL_RPATH "$ORIGIN/lib/ctp:$ORIGIN/lib/rohon"
    )
    target_link_libraries(${MD_API}
        ${CTP_BUILD_LIBS_DIR}/libthostmduserapi_se.so
    )
    # Boost 库链接
    if(BOOST_LIB_DIRS)
        target_link_libraries(${MD_API} ${BOOST_LIB_DIRS}/libboost_locale.so)
    else()
        find_library(BOOST_LOCALE_LIB boost_locale)
        if(BOOST_LOCALE_LIB)
            target_link_libraries(${MD_API} ${BOOST_LOCALE_LIB})
        else()
            target_link_libraries(${MD_API} boost_locale)
        endif()
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set_target_properties(${MD_API} PROPERTIES
        PREFIX ""
        SUFFIX ".pyd"
    )
    target_link_libraries(${MD_API}
        thostmduserapi_se.lib
    )
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set_target_properties(${MD_API} PROPERTIES
        PREFIX ""
        SUFFIX ".so"
        MACOSX_RPATH ON
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "@loader_path;@loader_path/lib/ctp"
    )
    # macOS: 添加 -undefined dynamic_lookup 以允许运行时解析 Python 符号
    target_link_options(${MD_API} PRIVATE "LINKER:-undefined,dynamic_lookup")
    # macOS: 使用 dylib 格式库
    target_link_libraries(${MD_API}
        ${CTP_BUILD_LIBS_DIR}/libthostmduserapi_se.dylib
    )
    # 如果找到 Boost，链接 Boost 库
    if(Boost_FOUND)
        find_library(BOOST_LOCALE_LIB boost_locale PATHS ${BOOST_LIB_DIRS} /opt/homebrew/lib)
        if(BOOST_LOCALE_LIB)
            target_link_libraries(${MD_API} ${BOOST_LOCALE_LIB})
        else()
            target_link_libraries(${MD_API} boost_locale)
        endif()
    endif()
endif()

# -----------------------------------------------------------------------------
# 安装目标 - 同时复制 CTP 和 Rohon 库到 package 目录
# -----------------------------------------------------------------------------
set(PACKAGE_DIR ${PROJECT_SOURCE_DIR}/../package/pyctp)

add_custom_target(copy_to_package ALL
    DEPENDS ${TD_API} ${MD_API}
    COMMENT "Copying built files to package directory"
)

# 复制交易 API（SWIG 生成的 Python 文件和动态模块）
add_custom_command(TARGET copy_to_package POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        ${TD_WRAPPER_PY}
        ${PACKAGE_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${TD_API}>
        ${PACKAGE_DIR}/
)

# 复制行情 API（SWIG 生成的 Python 文件和动态模块）
add_custom_command(TARGET copy_to_package POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        ${MD_WRAPPER_PY}
        ${PACKAGE_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${MD_API}>
        ${PACKAGE_DIR}/
)

# -----------------------------------------------------------------------------
# 复制所有实现（ctp 和 rohon）的库文件到 package/lib/
# -----------------------------------------------------------------------------

# 定义所有实现类型
set(CTP_IMPLEMENTATIONS ctp rohon)

foreach(IMPL ${CTP_IMPLEMENTATIONS})
    set(IMPL_LIBS_DIR ${PROJECT_SOURCE_DIR}/libs/${IMPL}/${CTP_PLATFORM})

    # 检查该实现是否存在
    if(EXISTS ${IMPL_LIBS_DIR})
        message(STATUS "Found implementation: ${IMPL}")

        # 根据平台定义库文件列表
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            set(IMPL_LIB_FILES
                ${IMPL_LIBS_DIR}/libthosttraderapi_se.so
                ${IMPL_LIBS_DIR}/libthostmduserapi_se.so
            )
            # 融航额外库
            if(IMPL STREQUAL "rohon")
                list(APPEND IMPL_LIB_FILES
                    ${IMPL_LIBS_DIR}/librohonbase.so
                    ${IMPL_LIBS_DIR}/libLinuxDataCollect.so
                )
            endif()
        elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
            set(IMPL_LIB_FILES
                ${IMPL_LIBS_DIR}/thosttraderapi_se.dll
                ${IMPL_LIBS_DIR}/thostmduserapi_se.dll
            )
            # 融航额外库
            if(IMPL STREQUAL "rohon")
                list(APPEND IMPL_LIB_FILES
                    ${IMPL_LIBS_DIR}/rohonbase.dll
                )
            endif()
        elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
            # macOS: 使用 dylib 格式库
            set(IMPL_LIB_FILES
                ${IMPL_LIBS_DIR}/libthosttraderapi_se.dylib
                ${IMPL_LIBS_DIR}/libthostmduserapi_se.dylib
            )
        endif()

        # 复制库文件到 package/lib/${IMPL}/
        foreach(lib_file ${IMPL_LIB_FILES})
            if(EXISTS ${lib_file})
                add_custom_command(TARGET copy_to_package POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E make_directory
                        ${PACKAGE_DIR}/lib/${IMPL}
                    COMMAND ${CMAKE_COMMAND} -E copy
                        ${lib_file}
                        ${PACKAGE_DIR}/lib/${IMPL}/
                    COMMENT "Copying ${lib_file} to package/lib/${IMPL}/"
                )
            endif()
        endforeach()
    else()
        message(WARNING "Implementation ${IMPL} not found at ${IMPL_LIBS_DIR}")
    endif()
endforeach()

# -----------------------------------------------------------------------------
# 打印配置信息
# -----------------------------------------------------------------------------
message(STATUS "")
message(STATUS "Configuration Summary:")
message(STATUS "  Platform: ${CTP_PLATFORM}")
message(STATUS "  Includes: ${CTP_INCLUDES_DIR}")
message(STATUS "  Build Libraries: ${CTP_BUILD_LIBS_DIR}")
message(STATUS "  Output: ${PACKAGE_DIR}")
message(STATUS "")

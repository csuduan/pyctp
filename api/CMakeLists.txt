cmake_minimum_required(VERSION 3.15)

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

# 查找 Python（扩展模块只需 Development.Module，不需要 Embed）
find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Module)
message(STATUS "Python3 found: ${Python3_EXECUTABLE}")
message(STATUS "Python3 include: ${Python3_INCLUDE_DIRS}")
message(STATUS "Python3 library: ${Python3_LIBRARIES}")

# 查找 Boost
if(DEFINED ENV{BOOST_INCLUDE})
    set(BOOST_INCLUDE_DIRS $ENV{BOOST_INCLUDE})
    set(BOOST_LIB_DIRS $ENV{BOOST_LIB})
    message(STATUS "Using Boost from environment: ${BOOST_INCLUDE_DIRS}")
else()
    if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        find_package(Boost REQUIRED COMPONENTS locale system)
    else()
        find_package(Boost REQUIRED)
    endif()
    if(Boost_FOUND)
        set(BOOST_INCLUDE_DIRS ${Boost_INCLUDE_DIRS})
        set(BOOST_LIB_DIRS ${Boost_LIBRARY_DIRS})
        message(STATUS "Boost found: ${Boost_VERSION}")
        message(STATUS "Boost include: ${Boost_INCLUDE_DIRS}")
        if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
            message(STATUS "Boost libraries: ${Boost_LIBRARIES}")
            message(STATUS "Boost library dirs: ${Boost_LIBRARY_DIRS}")
        endif()
    endif()
endif()

# -----------------------------------------------------------------------------
# 平台特定编译选项
# -----------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    add_compile_options(/bigobj /MD)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(CMAKE_MACOSX_RPATH ON)
endif()

# 查找 SWIG
find_program(SWIG_EXECUTABLE swig)
if(NOT SWIG_EXECUTABLE)
    message(FATAL_ERROR "SWIG not found. Please install SWIG.")
endif()

# -----------------------------------------------------------------------------
# 定义构建函数：为每个实现编译 SWIG 绑定
# -----------------------------------------------------------------------------
function(build_impl IMPL_NAME)
    set(IMPL_INCLUDES_DIR ${PROJECT_SOURCE_DIR}/libs/${IMPL_NAME}/${CTP_PLATFORM}/include)
    set(IMPL_BUILD_LIBS_DIR ${PROJECT_SOURCE_DIR}/libs/${IMPL_NAME}/${CTP_PLATFORM})

    if(NOT EXISTS ${IMPL_INCLUDES_DIR})
        message(WARNING "Implementation ${IMPL_NAME} includes not found at ${IMPL_INCLUDES_DIR}, skipping.")
        return()
    endif()
    if(NOT EXISTS ${IMPL_BUILD_LIBS_DIR})
        message(WARNING "Implementation ${IMPL_NAME} libraries not found at ${IMPL_BUILD_LIBS_DIR}, skipping.")
        return()
    endif()

    # Windows 链接需要对应的导入库
    if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        if(NOT EXISTS ${IMPL_BUILD_LIBS_DIR}/thosttraderapi_se.lib)
            message(WARNING "Implementation ${IMPL_NAME} missing thosttraderapi_se.lib on Windows, skipping.")
            return()
        endif()
        if(NOT EXISTS ${IMPL_BUILD_LIBS_DIR}/thostmduserapi_se.lib)
            message(WARNING "Implementation ${IMPL_NAME} missing thostmduserapi_se.lib on Windows, skipping.")
            return()
        endif()
    endif()

    message(STATUS "Building implementation: ${IMPL_NAME}")
    message(STATUS "  Includes: ${IMPL_INCLUDES_DIR}")
    message(STATUS "  Libraries: ${IMPL_BUILD_LIBS_DIR}")

    # 每个实现独立的构建子目录，避免并行编译时 .py 文件冲突
    set(IMPL_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR}/${IMPL_NAME})
    file(MAKE_DIRECTORY ${IMPL_BUILD_DIR})

    # 生成的文件路径（模块名保持统一，通过子目录隔离）
    set(TD_WRAPPER_CXX ${IMPL_BUILD_DIR}/thosttraderapi_wrap.cxx)
    set(TD_WRAPPER_PY ${IMPL_BUILD_DIR}/thosttraderapi.py)
    set(MD_WRAPPER_CXX ${IMPL_BUILD_DIR}/thostmduserapi_wrap.cxx)
    set(MD_WRAPPER_PY ${IMPL_BUILD_DIR}/thostmduserapi.py)

    # 目标名加后缀确保 CMake 内唯一，但输出库名保持统一
    set(TD_TARGET _thosttraderapi_${IMPL_NAME})
    set(MD_TARGET _thostmduserapi_${IMPL_NAME})

    # 生成交易 API 包装代码
    add_custom_command(
        OUTPUT ${TD_WRAPPER_CXX} ${TD_WRAPPER_PY}
        COMMAND ${SWIG_EXECUTABLE} -threads -c++ -python
            -module thosttraderapi
            -outdir ${IMPL_BUILD_DIR}
            -o ${TD_WRAPPER_CXX}
            -I${IMPL_INCLUDES_DIR}
            ${PROJECT_SOURCE_DIR}/thosttraderapi.i
        DEPENDS ${PROJECT_SOURCE_DIR}/thosttraderapi.i
            ${IMPL_INCLUDES_DIR}/ThostFtdcTraderApi.h
            ${IMPL_INCLUDES_DIR}/ThostFtdcUserApiDataType.h
            ${IMPL_INCLUDES_DIR}/ThostFtdcUserApiStruct.h
        COMMENT "Generating SWIG wrapper for thosttraderapi (${IMPL_NAME})"
    )

    # 生成行情 API 包装代码
    add_custom_command(
        OUTPUT ${MD_WRAPPER_CXX} ${MD_WRAPPER_PY}
        COMMAND ${SWIG_EXECUTABLE} -threads -c++ -python
            -module thostmduserapi
            -outdir ${IMPL_BUILD_DIR}
            -o ${MD_WRAPPER_CXX}
            -I${IMPL_INCLUDES_DIR}
            ${PROJECT_SOURCE_DIR}/thostmduserapi.i
        DEPENDS ${PROJECT_SOURCE_DIR}/thostmduserapi.i
            ${IMPL_INCLUDES_DIR}/ThostFtdcMdApi.h
            ${IMPL_INCLUDES_DIR}/ThostFtdcUserApiDataType.h
            ${IMPL_INCLUDES_DIR}/ThostFtdcUserApiStruct.h
        COMMENT "Generating SWIG wrapper for thostmduserapi (${IMPL_NAME})"
    )

    # 创建自定义目标确保 SWIG 文件被生成
    add_custom_target(swig_wrappers_${IMPL_NAME} ALL
        DEPENDS ${TD_WRAPPER_CXX} ${MD_WRAPPER_CXX}
    )

    # -----------------------------------------------------------------------------
    # 编译交易 API 模块
    # -----------------------------------------------------------------------------
    add_library(${TD_TARGET} SHARED ${TD_WRAPPER_CXX})
    add_dependencies(${TD_TARGET} swig_wrappers_${IMPL_NAME})

    set_target_properties(${TD_TARGET} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY ${IMPL_BUILD_DIR}
        RUNTIME_OUTPUT_DIRECTORY ${IMPL_BUILD_DIR}
        OUTPUT_NAME "_thosttraderapi"
    )

    target_include_directories(${TD_TARGET} PRIVATE
        ${IMPL_INCLUDES_DIR}
        ${Python3_INCLUDE_DIRS}
        ${BOOST_INCLUDE_DIRS}
    )

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set_target_properties(${TD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            BUILD_RPATH "$ORIGIN"
            INSTALL_RPATH "$ORIGIN"
        )
        target_link_libraries(${TD_TARGET}
            ${IMPL_BUILD_LIBS_DIR}/libthosttraderapi_se.so
        )
        if(BOOST_LIB_DIRS)
            target_link_libraries(${TD_TARGET}
                ${BOOST_LIB_DIRS}/libboost_locale.so
                ${BOOST_LIB_DIRS}/libboost_system.so
            )
        else()
            find_library(BOOST_LOCALE_LIB boost_locale)
            find_library(BOOST_SYSTEM_LIB boost_system)
            if(BOOST_LOCALE_LIB)
                target_link_libraries(${TD_TARGET} ${BOOST_LOCALE_LIB})
            else()
                target_link_libraries(${TD_TARGET} boost_locale)
            endif()
            if(BOOST_SYSTEM_LIB)
                target_link_libraries(${TD_TARGET} ${BOOST_SYSTEM_LIB})
            else()
                target_link_libraries(${TD_TARGET} boost_system)
            endif()
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set_target_properties(${TD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".pyd"
        )
        target_link_directories(${TD_TARGET} PRIVATE
            ${IMPL_BUILD_LIBS_DIR}
            ${Boost_LIBRARY_DIRS}
        )
        target_link_libraries(${TD_TARGET}
            ${Python3_LIBRARIES}
            ${Boost_LIBRARIES}
            thosttraderapi_se.lib
        )
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set_target_properties(${TD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            MACOSX_RPATH ON
            BUILD_WITH_INSTALL_RPATH ON
            INSTALL_RPATH "@loader_path"
        )
        target_link_options(${TD_TARGET} PRIVATE "LINKER:-undefined,dynamic_lookup")
        target_link_libraries(${TD_TARGET}
            ${IMPL_BUILD_LIBS_DIR}/libthosttraderapi_se.dylib
        )
        if(Boost_FOUND)
            find_library(BOOST_LOCALE_LIB boost_locale PATHS ${BOOST_LIB_DIRS} /opt/homebrew/lib)
            if(BOOST_LOCALE_LIB)
                target_link_libraries(${TD_TARGET} ${BOOST_LOCALE_LIB})
            else()
                target_link_libraries(${TD_TARGET} boost_locale)
            endif()
        endif()
    endif()

    # -----------------------------------------------------------------------------
    # 编译行情 API 模块
    # -----------------------------------------------------------------------------
    add_library(${MD_TARGET} SHARED ${MD_WRAPPER_CXX})
    add_dependencies(${MD_TARGET} swig_wrappers_${IMPL_NAME})

    set_target_properties(${MD_TARGET} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY ${IMPL_BUILD_DIR}
        RUNTIME_OUTPUT_DIRECTORY ${IMPL_BUILD_DIR}
        OUTPUT_NAME "_thostmduserapi"
    )

    target_include_directories(${MD_TARGET} PRIVATE
        ${IMPL_INCLUDES_DIR}
        ${Python3_INCLUDE_DIRS}
        ${BOOST_INCLUDE_DIRS}
    )

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set_target_properties(${MD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            BUILD_RPATH "$ORIGIN"
            INSTALL_RPATH "$ORIGIN"
        )
        target_link_libraries(${MD_TARGET}
            ${IMPL_BUILD_LIBS_DIR}/libthostmduserapi_se.so
        )
        if(BOOST_LIB_DIRS)
            target_link_libraries(${MD_TARGET}
                ${BOOST_LIB_DIRS}/libboost_locale.so
            )
        else()
            find_library(BOOST_LOCALE_LIB boost_locale)
            if(BOOST_LOCALE_LIB)
                target_link_libraries(${MD_TARGET} ${BOOST_LOCALE_LIB})
            else()
                target_link_libraries(${MD_TARGET} boost_locale)
            endif()
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set_target_properties(${MD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".pyd"
        )
        target_link_directories(${MD_TARGET} PRIVATE
            ${IMPL_BUILD_LIBS_DIR}
            ${Boost_LIBRARY_DIRS}
        )
        target_link_libraries(${MD_TARGET}
            ${Python3_LIBRARIES}
            ${Boost_LIBRARIES}
            thostmduserapi_se.lib
        )
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set_target_properties(${MD_TARGET} PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            MACOSX_RPATH ON
            BUILD_WITH_INSTALL_RPATH ON
            INSTALL_RPATH "@loader_path"
        )
        target_link_options(${MD_TARGET} PRIVATE "LINKER:-undefined,dynamic_lookup")
        target_link_libraries(${MD_TARGET}
            ${IMPL_BUILD_LIBS_DIR}/libthostmduserapi_se.dylib
        )
        if(Boost_FOUND)
            find_library(BOOST_LOCALE_LIB boost_locale PATHS ${BOOST_LIB_DIRS} /opt/homebrew/lib)
            if(BOOST_LOCALE_LIB)
                target_link_libraries(${MD_TARGET} ${BOOST_LOCALE_LIB})
            else()
                target_link_libraries(${MD_TARGET} boost_locale)
            endif()
        endif()
    endif()

    # -------------------------------------------------------------------------
    # 安装规则：将 SWIG 产物、扩展模块和预编译原生库放入 wheel
    # -------------------------------------------------------------------------
    install(FILES
        ${TD_WRAPPER_PY}
        ${MD_WRAPPER_PY}
        DESTINATION ctpx/${IMPL_NAME}
    )

    install(TARGETS
        ${TD_TARGET}
        ${MD_TARGET}
        LIBRARY DESTINATION ctpx/${IMPL_NAME}
        RUNTIME DESTINATION ctpx/${IMPL_NAME}
        ARCHIVE DESTINATION ctpx/${IMPL_NAME}
    )

    # 安装预编译原生库（.so / .dylib / .dll / .lib）
    file(GLOB IMPL_PREBUILT_LIBS
        "${IMPL_BUILD_LIBS_DIR}/*.so"
        "${IMPL_BUILD_LIBS_DIR}/*.dylib"
        "${IMPL_BUILD_LIBS_DIR}/*.dll"
        "${IMPL_BUILD_LIBS_DIR}/*.lib"
    )
    if(IMPL_PREBUILT_LIBS)
        install(FILES ${IMPL_PREBUILT_LIBS} DESTINATION ctpx/${IMPL_NAME})
    endif()

    # Linux：为 SONAME 不同的库创建符号链接，确保运行时加载器能找到
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND IMPL_PREBUILT_LIBS)
        foreach(lib_file ${IMPL_PREBUILT_LIBS})
            get_filename_component(lib_name ${lib_file} NAME)
            if(lib_name MATCHES "\\.so$")
                execute_process(
                    COMMAND readelf -d ${lib_file}
                    OUTPUT_VARIABLE readelf_out
                    ERROR_QUIET
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                )
                if(readelf_out MATCHES "SONAME[^[]*\\[([^]]*)\\]")
                    set(soname ${CMAKE_MATCH_1})
                    if(NOT soname STREQUAL lib_name)
                        install(CODE "
                            set(_link_path \"\${CMAKE_INSTALL_PREFIX}/ctpx/${IMPL_NAME}/${soname}\")
                            if(NOT EXISTS \"\${_link_path}\")
                                file(CREATE_LINK \"${lib_name}\" \"\${_link_path}\" SYMBOLIC)
                            endif()
                        ")
                    endif()
                endif()
            endif()
        endforeach()
    endif()

    # Linux：为第三方实现库设置 RPATH，使其在 $ORIGIN 中解析依赖
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND NOT IMPL_NAME STREQUAL "ctp")
        install(CODE "
            foreach(_lib_name libthosttraderapi_se.so libthostmduserapi_se.so)
                set(_lib_path \"\${CMAKE_INSTALL_PREFIX}/ctpx/${IMPL_NAME}/\${_lib_name}\")
                if(EXISTS \${_lib_path})
                    execute_process(
                        COMMAND patchelf --set-rpath \"\$ORIGIN\" \${_lib_path}
                        RESULT_VARIABLE _patchelf_result
                    )
                    if(NOT _patchelf_result EQUAL 0)
                        message(WARNING \"patchelf failed for \${_lib_path}\")
                    endif()
                endif()
            endforeach()
        ")
    endif()

endfunction()

# -----------------------------------------------------------------------------
# 为每个实现调用构建
# -----------------------------------------------------------------------------
set(CTP_IMPLEMENTATIONS ctp rohon jees)

foreach(IMPL ${CTP_IMPLEMENTATIONS})
    build_impl(${IMPL})
endforeach()

# -----------------------------------------------------------------------------
# 打印配置信息
# -----------------------------------------------------------------------------
message(STATUS "")
message(STATUS "Configuration Summary:")
message(STATUS "  Platform: ${CTP_PLATFORM}")
message(STATUS "  Implementations: ${CTP_IMPLEMENTATIONS}")
message(STATUS "")

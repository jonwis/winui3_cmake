# Funtion to run cppwinrt, generating headers from .winmd files
include_guard()

include("${CMAKE_CURRENT_LIST_DIR}/require_arguments.cmake")

# Run cppwinrt, generating headers from .winmd files
# (and other things)
#
# Single-value arguments:
# TARGET - Name of CMake target to generate
# OUT - Output directory
# PCH - Optional name of precompiled header
# COMPONENT - Optional component directory
# COMPONENT_NAME - Optional component name
#
# IN - List of input .winmd files
# REF - List of reference .winmd files
#
# OVERWRITE - Pass '-overwrite' argument to cppwinrt
# OPTIMIZE - Pass '-optimize' argument to cppwinrt
# PREFIX - Pass '-prefix' argument to cppwinrt
function(run_cppwinrt)
    cmake_parse_arguments(PARSE_ARGV 0 CPPWINRT "OVERWRITE;OPTIMIZE;PREFIX;BARE_COMPONENT"
        "TARGET;OUT;PCH;COMPONENT;COMPONENT_NAME;GENERATED_SOURCES;NAMESPACE;WINSDK_VERSION;TOOL;WORKING_DIRECTORY"
        "IN;REF;OUTPUTS;BYPRODUCTS;DEPENDS;ARGS")
    require_arguments(CPPWINRT TARGET OUT)
    if(NOT CPPWINRT_TOOL)
        include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/check_nuget_package.cmake")
        check_nuget_package(Microsoft.Windows.CppWinRT REQUIRED)
        set(CPPWINRT_TOOL "${Microsoft_Windows_CppWinRT_PATH}/bin/cppwinrt.exe")
    endif()
    if(NOT CPPWINRT_WORKING_DIRECTORY)
        set(CPPWINRT_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH CPPWINRT_OUT BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)
    # NAMESPACE, WINSDK_VERSION are unused and only here so "common arguments" can be added
    string(MAKE_C_IDENTIFIER "${CPPWINRT_TARGET}" target_ident)
    set(cppwinrt_args "")
    foreach(input_arg ${CPPWINRT_IN})
        list(APPEND cppwinrt_args "-in" "${input_arg}")
    endforeach()
    foreach(ref_arg ${CPPWINRT_REF})
        list(APPEND cppwinrt_args "-ref" "${ref_arg}")
    endforeach()
    if(CPPWINRT_OUT)
        list(APPEND cppwinrt_args "-out" "${CPPWINRT_OUT}")
    endif()
    if(CPPWINRT_BARE_COMPONENT)
        list(APPEND cppwinrt_args "-comp")
    elseif(CPPWINRT_COMPONENT)
        list(APPEND cppwinrt_args "-comp" "${CPPWINRT_COMPONENT}")
    endif()
    if((CPPWINRT_COMPONENT OR CPPWINRT_BARE_COMPONENT) AND CPPWINRT_COMPONENT_NAME)
        list(APPEND cppwinrt_args "-name" "${CPPWINRT_COMPONENT_NAME}")
    endif()
    if(CPPWINRT_PCH)
        list(APPEND cppwinrt_args "-pch" "${CPPWINRT_PCH}")
    endif()
    if(CPPWINRT_OVERWRITE)
        list(APPEND cppwinrt_args "-overwrite")
    endif()
    if(CPPWINRT_OPTIMIZE)
        list(APPEND cppwinrt_args "-optimize")
    endif()
    if(CPPWINRT_PREFIX)
        list(APPEND cppwinrt_args "-prefix")
    endif()

    set(generated_sources "")
    if(CPPWINRT_COMPONENT OR CPPWINRT_BARE_COMPONENT)
        list(APPEND generated_sources "${CPPWINRT_OUT}/module.g.cpp")
    endif()

    set(stamp_file "${CPPWINRT_OUT}/.${target_ident}.stamp")
    set(metadata_dependencies "")
    foreach(metadata IN LISTS CPPWINRT_IN CPPWINRT_REF)
        cmake_path(ABSOLUTE_PATH metadata BASE_DIRECTORY "${CPPWINRT_WORKING_DIRECTORY}" NORMALIZE)
        if(IS_DIRECTORY "${metadata}")
            file(GLOB_RECURSE metadata_files CONFIGURE_DEPENDS "${metadata}/*.winmd")
            list(APPEND metadata_dependencies ${metadata_files})
        else()
            list(APPEND metadata_dependencies "${metadata}")
        endif()
    endforeach()
    set(outputs "${stamp_file}" ${generated_sources} ${CPPWINRT_OUTPUTS})
    list(REMOVE_DUPLICATES outputs)
    add_custom_command(OUTPUT ${outputs}
                       BYPRODUCTS ${CPPWINRT_BYPRODUCTS}
                       COMMAND "${CMAKE_COMMAND}" -E make_directory "${CPPWINRT_OUT}"
                       COMMAND "${CPPWINRT_TOOL}" ${cppwinrt_args} ${CPPWINRT_ARGS}
                       COMMAND "${CMAKE_COMMAND}" -E touch "${stamp_file}"
                       DEPENDS "${CPPWINRT_TOOL}" ${metadata_dependencies} ${CPPWINRT_DEPENDS}
                       WORKING_DIRECTORY "${CPPWINRT_WORKING_DIRECTORY}" VERBATIM
                       COMMENT "Running cppwinrt for ${CPPWINRT_TARGET}")
    add_custom_target(${CPPWINRT_TARGET} DEPENDS ${outputs})

    if(CPPWINRT_GENERATED_SOURCES)
        set(${CPPWINRT_GENERATED_SOURCES} "${generated_sources}" PARENT_SCOPE)
    endif()
endfunction()

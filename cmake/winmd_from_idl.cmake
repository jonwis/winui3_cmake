# Convert an .idl file to .winmd
include_guard()

include("${CMAKE_CURRENT_LIST_DIR}/require_arguments.cmake")

# Convert an .idl file to .winmd
#
# OUT - Output .winmd name
# IN - Input .idl name
# WINSDK_VERSION - Windows SDK version used to locate native metadata
# REF - Reference .winmd files to use
function(winmd_from_idl)
    cmake_parse_arguments(PARSE_ARGV 0 winmd_from_idl "NO_DEFAULT_ARGS"
        "OUT;IN;WINSDK_VERSION;NAMESPACE;PCH;TOOL;METADATA_DIR;WORKING_DIRECTORY"
        "REF;INCLUDE_DIRS;ARGS;DEPENDS;OUTPUTS;BYPRODUCTS")
    # NAMESPACE, PCH are unused and only here so "common arguments" can be added
    require_arguments(winmd_from_idl OUT IN)
    if(NOT winmd_from_idl_TOOL)
        include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/sdk_buildtools.cmake")
        find_sdk_buildtool(MIDL midl REQUIRED)
        set(winmd_from_idl_TOOL "${MIDL}")
    endif()
    if(NOT winmd_from_idl_WORKING_DIRECTORY)
        set(winmd_from_idl_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH winmd_from_idl_OUT
        BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)

    cmake_path(NATIVE_PATH winmd_from_idl_IN idl_native)
    cmake_path(NATIVE_PATH winmd_from_idl_OUT winmd_native)
    set(midl_args ${winmd_from_idl_ARGS})
    if(NOT winmd_from_idl_NO_DEFAULT_ARGS)
        if(NOT winmd_from_idl_METADATA_DIR)
            require_arguments(winmd_from_idl WINSDK_VERSION)
            include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/find_platform_winmds.cmake")
            find_platform_package_dir(PACKAGE windows.foundation.foundationcontract
                PATH_VAR winmd_from_idl_METADATA_DIR WINSDK_VERSION "${winmd_from_idl_WINSDK_VERSION}")
        endif()
        list(PREPEND midl_args /nologo /winrt /nomidl /h nul)
    endif()
    list(APPEND midl_args /winmd "${winmd_native}")
    if(winmd_from_idl_METADATA_DIR)
        list(APPEND midl_args /metadata_dir "${winmd_from_idl_METADATA_DIR}")
    endif()
    foreach(include_dir IN LISTS winmd_from_idl_INCLUDE_DIRS)
        list(APPEND midl_args /I "${include_dir}")
    endforeach()
    foreach(ref_path IN LISTS winmd_from_idl_REF)
        cmake_path(NATIVE_PATH ref_path ref_native)
        list(APPEND midl_args /reference "${ref_native}")
    endforeach()
    set(metadata_dependencies "")
    foreach(metadata IN LISTS winmd_from_idl_REF)
        cmake_path(ABSOLUTE_PATH metadata BASE_DIRECTORY "${winmd_from_idl_WORKING_DIRECTORY}" NORMALIZE)
        if(IS_DIRECTORY "${metadata}")
            file(GLOB_RECURSE metadata_files CONFIGURE_DEPENDS "${metadata}/*.winmd")
            list(APPEND metadata_dependencies ${metadata_files})
        else()
            list(APPEND metadata_dependencies "${metadata}")
        endif()
    endforeach()
    if(winmd_from_idl_METADATA_DIR)
        set(metadata "${winmd_from_idl_METADATA_DIR}")
        cmake_path(ABSOLUTE_PATH metadata BASE_DIRECTORY "${winmd_from_idl_WORKING_DIRECTORY}" NORMALIZE)
        if(IS_DIRECTORY "${metadata}")
            file(GLOB_RECURSE metadata_files CONFIGURE_DEPENDS "${metadata}/*.winmd")
            list(APPEND metadata_dependencies ${metadata_files})
        endif()
    endif()
    cmake_path(ABSOLUTE_PATH winmd_from_idl_IN
        BASE_DIRECTORY "${winmd_from_idl_WORKING_DIRECTORY}" NORMALIZE OUTPUT_VARIABLE idl_dependency)
    cmake_path(GET winmd_from_idl_OUT PARENT_PATH output_dir)
    if(NOT output_dir)
        set(output_dir "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
    add_custom_command(OUTPUT "${winmd_from_idl_OUT}" ${winmd_from_idl_OUTPUTS}
        BYPRODUCTS ${winmd_from_idl_BYPRODUCTS}
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${output_dir}"
        COMMAND "${winmd_from_idl_TOOL}" ${midl_args} "${idl_native}"
        MAIN_DEPENDENCY "${idl_dependency}"
        DEPENDS "${winmd_from_idl_TOOL}" ${metadata_dependencies} ${winmd_from_idl_DEPENDS}
        WORKING_DIRECTORY "${winmd_from_idl_WORKING_DIRECTORY}"
        VERBATIM)
endfunction()

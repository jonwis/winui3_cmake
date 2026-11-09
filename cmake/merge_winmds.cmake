# Merge multiple .winmd files
include_guard()

include("${CMAKE_CURRENT_LIST_DIR}/require_arguments.cmake")

# Merge multiple .winmd files
#
# TARGET - Target for .winmd merging
# OUTDIR - Output directory
# NAMESPACE - Namespace of declarations in .winmds
# IN - .winmds to merge
# REF - Reference .winmd files to use
function(merge_winmds)
    cmake_parse_arguments(PARSE_ARGV 0 merge_winmds "NO_PARTIAL"
        "TARGET;OUTDIR;NAMESPACE;WINSDK_VERSION;PCH;TOOL;DEPTH;WORKING_DIRECTORY"
        "IN;REF;OUTPUTS;METADATA_DIRS;ARGS;DEPENDS")
    # WINSDK_VERSION, PCH are unused and only here so "common arguments" can be added
    require_arguments(merge_winmds TARGET OUTDIR)
    if(NOT merge_winmds_TOOL)
        include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/sdk_buildtools.cmake")
        find_sdk_buildtool(MDMERGE mdmerge REQUIRED)
        set(merge_winmds_TOOL "${MDMERGE}")
    endif()
    if(NOT merge_winmds_WORKING_DIRECTORY)
        set(merge_winmds_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH merge_winmds_OUTDIR BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)
    if(NOT merge_winmds_OUTPUTS)
        require_arguments(merge_winmds NAMESPACE)
        set(merge_winmds_OUTPUTS "${merge_winmds_OUTDIR}/${merge_winmds_NAMESPACE}.winmd")
    endif()
    if(NOT merge_winmds_DEPTH)
        set(merge_winmds_DEPTH 1)
    endif()

    set(winmd_ref_paths "")
    foreach(ref_path IN LISTS merge_winmds_REF)
        cmake_path(GET ref_path PARENT_PATH ref_path)
        cmake_path(CONVERT "${ref_path}" TO_NATIVE_PATH_LIST ref_path_native)
        list(APPEND winmd_ref_paths "${ref_path_native}")
    endforeach()
    # mdmerge produces errors if duplicate metadata_dirs are passed
    list(REMOVE_DUPLICATES winmd_ref_paths)
    if(DEFINED merge_winmds_METADATA_DIRS)
        set(winmd_ref_paths ${merge_winmds_METADATA_DIRS})
    endif()
    set(metadata_dependencies "")
    foreach(metadata_dir IN LISTS winmd_ref_paths)
        cmake_path(ABSOLUTE_PATH metadata_dir BASE_DIRECTORY "${merge_winmds_WORKING_DIRECTORY}" NORMALIZE)
        if(IS_DIRECTORY "${metadata_dir}")
            file(GLOB_RECURSE metadata_files CONFIGURE_DEPENDS "${metadata_dir}/*.winmd")
            list(APPEND metadata_dependencies ${metadata_files})
        endif()
    endforeach()
    set(input_dependencies "")
    foreach(input IN LISTS merge_winmds_IN merge_winmds_REF)
        cmake_path(ABSOLUTE_PATH input BASE_DIRECTORY "${merge_winmds_WORKING_DIRECTORY}" NORMALIZE)
        list(APPEND input_dependencies "${input}")
    endforeach()
    set(winmd_args "")
    foreach(ref_path IN LISTS winmd_ref_paths)
        list(APPEND winmd_args -metadata_dir "${ref_path}")
    endforeach()
    foreach(in_path IN LISTS merge_winmds_IN)
        list(APPEND winmd_args -i "${in_path}")
    endforeach()
    if(NOT merge_winmds_NO_PARTIAL)
        list(APPEND winmd_args -partial)
    endif()
    if(NOT merge_winmds_DEPTH STREQUAL "DEFAULT")
        list(APPEND winmd_args "-n:${merge_winmds_DEPTH}")
    endif()
    list(APPEND winmd_args ${merge_winmds_ARGS})
    set(inventory "${CMAKE_CURRENT_BINARY_DIR}/${merge_winmds_TARGET}.winmd-outputs")
    set(owned "${merge_winmds_OUTDIR}/.${merge_winmds_TARGET}.owned-outputs")
    set(normalized_outputs "")
    foreach(output IN LISTS merge_winmds_OUTPUTS)
        cmake_path(ABSOLUTE_PATH output BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            NORMALIZE OUTPUT_VARIABLE output_absolute)
        list(APPEND normalized_outputs "${output_absolute}")
    endforeach()
    list(JOIN normalized_outputs "\n" inventory_contents)
    file(GENERATE OUTPUT "${inventory}" CONTENT "${inventory_contents}\n")
    set(prune_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/prune_outputs.cmake")
    add_custom_command(OUTPUT ${merge_winmds_OUTPUTS}
        BYPRODUCTS "${owned}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${merge_winmds_OUTDIR}"
        COMMAND "${merge_winmds_TOOL}" -o "${merge_winmds_OUTDIR}" ${winmd_args}
        COMMAND "${CMAKE_COMMAND}" "-DROOT=${merge_winmds_OUTDIR}" "-DOWNED=${owned}"
            "-DINVENTORY=${inventory}" -P "${prune_script}"
        DEPENDS "${merge_winmds_TOOL}" ${input_dependencies}
            ${metadata_dependencies} ${merge_winmds_DEPENDS} "${inventory}" "${prune_script}"
        WORKING_DIRECTORY "${merge_winmds_WORKING_DIRECTORY}" VERBATIM)
    add_custom_target(${merge_winmds_TARGET}
                      DEPENDS ${merge_winmds_OUTPUTS})
endfunction(merge_winmds)

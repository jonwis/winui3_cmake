# Copyright (c) Microsoft Corporation. All rights reserved.
cmake_minimum_required(VERSION 3.24)
project(metadata_dependencies LANGUAGES NONE)

include("${GENERATOR_MODULE_DIR}/merge_winmds.cmake")
file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/configure.log" "configure\n")
foreach(input IN ITEMS input.idl reference.idl Source.winmd Extra.winmd)
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${input}")
        file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/${input}" "synthetic input\n")
    endif()
endforeach()
set(generated "${CMAKE_CURRENT_BINARY_DIR}/generated metadata")
file(MAKE_DIRECTORY "${generated}")
add_custom_command(OUTPUT "${generated}/Input.winmd"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${generated}"
    COMMAND "${CMAKE_COMMAND}" -E copy "${CMAKE_CURRENT_SOURCE_DIR}/input.idl" "${generated}/Input.winmd"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/input.idl" VERBATIM)
add_custom_command(OUTPUT "${generated}/Reference.winmd"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${generated}"
    COMMAND "${CMAKE_COMMAND}" -E copy "${CMAKE_CURRENT_SOURCE_DIR}/reference.idl" "${generated}/Reference.winmd"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/reference.idl" VERBATIM)

if(EXPLICIT_MODE)
    set(dependency_mode EXPLICIT_DEPENDENCIES)
    set(references "${generated}/Reference.winmd" Source.winmd)
    set(extra_dependencies "${CMAKE_CURRENT_SOURCE_DIR}/Extra.winmd")
else()
    set(dependency_mode "")
    set(references "")
    set(extra_dependencies "${generated}/Reference.winmd")
endif()
set(output "${CMAKE_CURRENT_BINARY_DIR}/merged/Contoso.winmd")
merge_winmds(TARGET merged OUTDIR "${CMAKE_CURRENT_BINARY_DIR}/merged"
    TOOL "${FIXTURE_TOOL}" NAMESPACE Contoso
    ${dependency_mode}
    IN "${generated}/Input.winmd" REF ${references}
    METADATA_DIRS "${generated}" "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS ${extra_dependencies}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    ARGS --kind merge --outputs "${output}"
        --log "${CMAKE_CURRENT_BINARY_DIR}/merge.jsonl")

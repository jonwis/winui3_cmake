# Copyright (c) Microsoft Corporation. All rights reserved.
cmake_minimum_required(VERSION 3.24)

# Run with cmake -DTEST_BINARY_DIR=<build directory> -DCMAKE_MAKE_PROGRAM=<ninja> -P <this file>.
if(NOT CMAKE_SCRIPT_MODE_FILE)
    include("${MERGE_WINMDS_FILE}")
    set(work "${CMAKE_CURRENT_BINARY_DIR}/working directory")
    file(MAKE_DIRECTORY "${work}/first" "${work}/second" "${work}/third")
    file(WRITE "${work}/input.winmd" "synthetic input\n")
    foreach(dir IN ITEMS first second third)
        file(WRITE "${work}/${dir}/Reference.winmd" "synthetic reference\n")
    endforeach()
    set(first "${work}/first")
    set(second "${work}/second")
    set(third "${work}/third")
    cmake_path(CONVERT "${first}" TO_NATIVE_PATH_LIST native_first)
    string(TOUPPER "${first}" upper_first)
    set(dirs second ./first "${second}/." "${native_first}" "third/../third" "${third}/")
    set(refs second/Reference.winmd ./first/Reference.winmd
        "${second}/./Reference.winmd" "${first}/Reference.winmd" third/Reference.winmd)
    if(CMAKE_HOST_WIN32)
        list(PREPEND dirs SeCoNd)
        list(PREPEND refs SeCoNd/Reference.winmd)
        list(APPEND dirs "${upper_first}")
        list(APPEND refs "${upper_first}/Reference.winmd" "${native_first}\\Reference.winmd")
    endif()
    merge_winmds(TARGET explicit OUTDIR "${CMAKE_CURRENT_BINARY_DIR}/explicit"
        TOOL "${TOOL}" IN input.winmd REF third/Reference.winmd METADATA_DIRS ${dirs}
        NAMESPACE Contoso WORKING_DIRECTORY "${work}"
        ARGS --kind merge --outputs "${CMAKE_CURRENT_BINARY_DIR}/explicit/Contoso.winmd"
        --log "${CMAKE_CURRENT_BINARY_DIR}/explicit.jsonl")
    merge_winmds(TARGET references OUTDIR "${CMAKE_CURRENT_BINARY_DIR}/references"
        TOOL "${TOOL}" IN input.winmd REF ${refs}
        NAMESPACE Contoso WORKING_DIRECTORY "${work}"
        ARGS --kind merge --outputs "${CMAKE_CURRENT_BINARY_DIR}/references/Contoso.winmd"
        --log "${CMAKE_CURRENT_BINARY_DIR}/references.jsonl")
    merge_winmds(TARGET override OUTDIR "${CMAKE_CURRENT_BINARY_DIR}/override"
        TOOL "${TOOL}" IN input.winmd REF third/Reference.winmd METADATA_DIRS ./second second
        NAMESPACE Contoso WORKING_DIRECTORY "${work}"
        ARGS --kind merge --outputs "${CMAKE_CURRENT_BINARY_DIR}/override/Contoso.winmd"
        --log "${CMAKE_CURRENT_BINARY_DIR}/override.jsonl")
    add_custom_target(check ALL DEPENDS explicit references override)
    return()
endif()

if(NOT DEFINED TEST_BINARY_DIR OR NOT DEFINED CMAKE_MAKE_PROGRAM)
    message(FATAL_ERROR "TEST_BINARY_DIR and CMAKE_MAKE_PROGRAM are required")
endif()
cmake_path(ABSOLUTE_PATH TEST_BINARY_DIR NORMALIZE)
if(NOT DEFINED MERGE_WINMDS_FILE)
    set(MERGE_WINMDS_FILE "${CMAKE_CURRENT_LIST_DIR}/../../cmake/merge_winmds.cmake")
endif()
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}/source")
file(WRITE "${TEST_BINARY_DIR}/source/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.24)\nproject(metadata_directories LANGUAGES NONE)\ninclude(\"${CMAKE_CURRENT_LIST_FILE}\")\n")
set(tool "${TEST_BINARY_DIR}/fake tool.exe")
execute_process(COMMAND powershell -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_LIST_DIR}/prepare_tool.ps1" -Output "${tool}"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${TEST_BINARY_DIR}/source" -B "${TEST_BINARY_DIR}"
    -G Ninja "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}" "-DTOOL=${tool}"
    "-DMERGE_WINMDS_FILE=${MERGE_WINMDS_FILE}" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" --build "${TEST_BINARY_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)

set(failures "")
foreach(case IN ITEMS explicit references override)
    file(STRINGS "${TEST_BINARY_DIR}/${case}.jsonl" records)
    list(GET records -1 arguments)
    string(JSON length LENGTH "${arguments}")
    math(EXPR last "${length} - 1")
    set(actual "")
    foreach(index RANGE 0 ${last})
        string(JSON argument GET "${arguments}" ${index})
        if(argument STREQUAL "-metadata_dir")
            math(EXPR next "${index} + 1")
            string(JSON directory GET "${arguments}" ${next})
            list(APPEND actual "${directory}")
        endif()
    endforeach()
    set(expected "")
    set(dirs second first third)
    if(CMAKE_HOST_WIN32)
        set(dirs SeCoNd first third)
    endif()
    if(case STREQUAL "override")
        set(dirs second)
    endif()
    foreach(dir IN LISTS dirs)
        cmake_path(CONVERT "${TEST_BINARY_DIR}/working directory/${dir}"
            TO_NATIVE_PATH_LIST directory)
        list(APPEND expected "${directory}")
    endforeach()
    if(NOT actual STREQUAL expected)
        string(APPEND failures "\n${case}: expected [${expected}], got [${actual}]")
    endif()
endforeach()
if(failures)
    message(FATAL_ERROR "Metadata directory deduplication/order/native spelling failed:${failures}")
endif()
message(STATUS "PASS: explicit and REF-derived metadata directory equivalence, order, and override")

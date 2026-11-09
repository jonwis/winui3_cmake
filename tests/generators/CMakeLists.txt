# Copyright (c) Microsoft Corporation. All rights reserved.
cmake_minimum_required(VERSION 3.24)
project(generator_scheduling LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/winmd_from_idl.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/merge_winmds.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/run_cppwinrt.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/make_pri.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/generate_XamlMetaDataProvider.cmake")

set(tool "${CMAKE_CURRENT_BINARY_DIR}/fake tool.exe")
set(root "${CMAKE_CURRENT_BINARY_DIR}/outputs with spaces")
set(input "${CMAKE_CURRENT_BINARY_DIR}/input.idl")
set(import "${CMAKE_CURRENT_BINARY_DIR}/import.idl")
set(ref "${CMAKE_CURRENT_BINARY_DIR}/references/Contoso.Reference.winmd")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/references")
set(config "${CMAKE_CURRENT_BINARY_DIR}/options.txt")
foreach(file IN ITEMS "${input}" "${import}" "${config}")
    if(NOT EXISTS "${file}")
        file(WRITE "${file}" "synthetic input\n")
    endif()
endforeach()
add_custom_command(OUTPUT "${ref}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/references"
    COMMAND "${CMAKE_COMMAND}" -E touch "${ref}"
    VERBATIM)
add_custom_target(reference DEPENDS "${ref}")

winmd_from_idl(IN "${input}" OUT "${root}/Contoso.Input.winmd"
    TOOL "${tool}" METADATA_DIR "${CMAKE_CURRENT_BINARY_DIR}/references"
    REF "${ref}" INCLUDE_DIRS "${CMAKE_CURRENT_BINARY_DIR}/include with spaces"
    ARGS --kind midl --log "${CMAKE_CURRENT_BINARY_DIR}/midl.jsonl"
    DEPENDS "${import}" "${config}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
winmd_from_idl(IN input.idl OUT "${root}/Tailspin.Input.winmd"
    REF references/Contoso.Reference.winmd
    TOOL "${tool}" NO_DEFAULT_ARGS ARGS /winrt /W1 /char signed
    --kind midl --log "${CMAKE_CURRENT_BINARY_DIR}/midl-custom.jsonl"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
set(merge_outputs "${root}/merged/Contoso.winmd")
if(NOT SHRINK_OUTPUTS)
    list(APPEND merge_outputs "${root}/merged/Tailspin.winmd")
endif()
list(JOIN merge_outputs "|" fake_outputs)
merge_winmds(TARGET merged OUTDIR "${root}/merged" TOOL "${tool}"
    IN "${root}/Contoso.Input.winmd" REF "${ref}" OUTPUTS ${merge_outputs}
    METADATA_DIRS "${CMAKE_CURRENT_BINARY_DIR}/references" "${CMAKE_CURRENT_BINARY_DIR}/references"
    DEPTH 3 ARGS --kind merge --outputs "${fake_outputs}"
    --log "${CMAKE_CURRENT_BINARY_DIR}/merge.jsonl")
merge_winmds(TARGET default_merged OUTDIR "${root}/default" TOOL "${tool}"
    NAMESPACE Contoso DEPTH DEFAULT NO_PARTIAL IN "outputs with spaces/Contoso.Input.winmd"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    ARGS --kind merge --outputs "${root}/default/Contoso.winmd"
    --log "${CMAKE_CURRENT_BINARY_DIR}/default-merge.jsonl")
merge_winmds(TARGET zero_merged OUTDIR "${root}/zero" TOOL "${tool}"
    NAMESPACE Tailspin DEPTH 0 IN "${root}/Contoso.Input.winmd"
    ARGS --kind merge --outputs "${root}/zero/Tailspin.winmd"
    --log "${CMAKE_CURRENT_BINARY_DIR}/zero-merge.jsonl")

set(component "${root}/component")
run_cppwinrt(TARGET component OUT "${component}" TOOL "${tool}"
    IN "${root}/merged/Contoso.winmd" REF "${CMAKE_CURRENT_BINARY_DIR}/references"
    COMPONENT "${component}/sources" COMPONENT_NAME Contoso PCH .
    OPTIMIZE OVERWRITE PREFIX OUTPUTS "${component}/Contoso.g.h"
    BYPRODUCTS "${component}/sources/Contoso.h"
    ARGS --kind component --outputs "${component}/Contoso.g.h|${component}/sources/Contoso.h"
    --log "${CMAKE_CURRENT_BINARY_DIR}/component.jsonl")
run_cppwinrt(TARGET bare OUT "${root}/bare" TOOL "${tool}"
    IN "${root}/Tailspin.Input.winmd" BARE_COMPONENT
    OUTPUTS "${root}/bare/Tailspin.g.h"
    ARGS --kind component --outputs "${root}/bare/Tailspin.g.h"
    --log "${CMAKE_CURRENT_BINARY_DIR}/bare.jsonl")

make_pri(OUTPUT "${root}/empty.pri" DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    TOOL "${tool}" EMPTY INDEX_NAME Contoso
    ARGS --kind pri --log "${CMAKE_CURRENT_BINARY_DIR}/empty.jsonl")
if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/strings.resw")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/strings.resw" "<root />")
endif()
make_pri(OUTPUT "${root}/resources.pri" DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    TOOL "${tool}" RESOURCE_INPUTS INDEX_NAME Contoso FILES strings.resw
    DEPENDS "${config}" ARGS --kind pri --log "${CMAKE_CURRENT_BINARY_DIR}/resources.jsonl")
make_pri(OUTPUT "${root}/native.pri" DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    TOOL "${tool}" FILES strings.resw
    ARGS --kind pri --log "${CMAKE_CURRENT_BINARY_DIR}/native.jsonl")
configure_file("${CMAKE_CURRENT_LIST_DIR}/custom.xml" "${CMAKE_CURRENT_BINARY_DIR}/custom.xml" COPYONLY)
make_pri(OUTPUT "${root}/custom.pri" TOOL "${tool}"
    CONFIG_XML "${CMAKE_CURRENT_BINARY_DIR}/custom.xml" PROJECT_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ARGS --kind pri --log "${CMAKE_CURRENT_BINARY_DIR}/custom.jsonl")
make_pri(OUTPUT "${root}/failure.pri" DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    TOOL "${tool}" EMPTY ARGS --kind fail --log "${CMAKE_CURRENT_BINARY_DIR}/failure.jsonl")
add_custom_target(failure DEPENDS "${root}/failure.pri")
add_custom_target(check ALL DEPENDS merged default_merged zero_merged component bare
    "${root}/Tailspin.Input.winmd" "${root}/empty.pri" "${root}/resources.pri"
    "${root}/native.pri" "${root}/custom.pri")

set(ROOT_NAMESPACE WrongAmbientNamespace)
generate_XamlMetaDataProvider(OUTDIR "${root}/provider" IDL_VAR provider_idl
    CPP_VAR provider_cpp NAMESPACE Contoso PCH fixture.h)

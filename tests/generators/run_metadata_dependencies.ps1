# Copyright (c) Microsoft Corporation. All rights reserved.
param(
    [Parameter(Mandatory)] [string] $CMake,
    [Parameter(Mandatory)] [string] $Ninja,
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'build metadata dependencies')
)
$ErrorActionPreference = 'Stop'
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
if (Test-Path -LiteralPath $BuildDirectory) {
    throw "Use a fresh build directory: $BuildDirectory"
}
New-Item -ItemType Directory -Path $BuildDirectory | Out-Null
$tool = Join-Path $BuildDirectory 'fake tool.exe'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare_tool.ps1') -Output $tool
if ($LASTEXITCODE -ne 0) { throw 'Fake tool preparation failed' }
function Assert([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}
function RunCMake([string[]] $arguments) {
    $output = & $CMake @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
}
function Count([string] $path) {
    if (Test-Path -LiteralPath $path) { return @(Get-Content -LiteralPath $path).Count }
    return 0
}
function Touch([string] $path) {
    Start-Sleep -Milliseconds 1100
    (Get-Item -LiteralPath $path).LastWriteTime = Get-Date
}
foreach ($mode in @('explicit', 'legacy')) {
    $source = Join-Path $BuildDirectory "$mode source"
    $build = Join-Path $BuildDirectory "$mode build"
    New-Item -ItemType Directory -Path $source | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'metadata_dependencies.cmake') -Destination (Join-Path $source 'CMakeLists.txt')
    $explicit = if ($mode -eq 'explicit') { 'ON' } else { 'OFF' }
    RunCMake @('-S', $source, '-B', $build, '-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$Ninja",
        "-DGENERATOR_MODULE_DIR=$PSScriptRoot\..\..\cmake", "-DFIXTURE_TOOL=$tool", "-DEXPLICIT_MODE=$explicit")
    $configureLog = Join-Path $build 'configure.log'
    $mergeLog = Join-Path $build 'merge.jsonl'
    $output = Join-Path $build 'merged\Contoso.winmd'
    $reference = Join-Path $build 'generated metadata\Reference.winmd'
    function Build { RunCMake @('--build', $build, '--target', 'merged') }
    Build
    Assert ((Count $mergeLog) -eq 1) "$mode first merge must run once"
    Assert (Test-Path -LiteralPath $reference) "$mode must produce the generated reference"
    if ($mode -eq 'explicit') {
        Assert ((Count $configureLog) -eq 1) 'First generated WinMDs must not rerun CMake'
        $query = & $Ninja -C $build -t query 'merged/Contoso.winmd' 2>&1
        Assert ($LASTEXITCODE -eq 0) 'Ninja dependency query failed'
        $query = $query -join "`n"
        foreach ($dependency in @('Source.winmd', 'Extra.winmd', 'generated metadata/Reference.winmd', 'generated metadata/Input.winmd')) {
            Assert ($query.Replace('\', '/').Contains($dependency)) "Missing actual file prerequisite: $dependency"
        }
    }
    Build
    if ($mode -eq 'explicit') {
        Assert ((Count $configureLog) -eq 1) 'Populating generated metadata must not rerun CMake on the next build'
    }
    $settledConfigureCount = Count $configureLog
    Assert ((Count $mergeLog) -eq 1) "$mode settled build must be no-op"
    foreach ($input in @((Join-Path $source 'Source.winmd'), $reference, (Join-Path $source 'Extra.winmd'))) {
        $before = Count $mergeLog
        Touch $input
        Build
        Assert ((Count $mergeLog) -eq ($before + 1)) "$mode reference change must rerun merge: $input"
        Assert ((Count $configureLog) -eq $settledConfigureCount) "$mode reference content changes must not rerun CMake"
    }
    $before = Count $mergeLog
    Touch (Join-Path $source 'reference.idl')
    Build
    Assert ((Count $mergeLog) -eq ($before + 1)) "$mode generated-reference producer change must rerun merge"
    foreach ($missing in @($output, $reference)) {
        $before = Count $mergeLog
        Remove-Item -LiteralPath $missing
        Build
        Assert (Test-Path -LiteralPath $missing) "$mode missing file must recover: $missing"
        Assert ((Count $mergeLog) -eq ($before + 1)) "$mode missing file must rerun merge once: $missing"
    }
    if ($mode -eq 'explicit') {
        Assert ((Count $configureLog) -eq $settledConfigureCount) 'Deleting generated files must not rerun CMake'
        $before = Count $mergeLog
        RunCMake @('--build', $build, '--target', 'clean')
        Build
        Assert ((Count $mergeLog) -eq ($before + 1)) 'Clean/rebuild must rerun merge once'
        Assert ((Count $configureLog) -eq $settledConfigureCount) 'Clean/rebuild must not rerun CMake'
        $before = Count $mergeLog
        Remove-Item -LiteralPath (Join-Path $build 'generated metadata') -Recurse
        Build
        Assert ((Count $mergeLog) -eq ($before + 1)) 'Deleted generated directory must recover'
        Assert ((Count $configureLog) -eq $settledConfigureCount) 'Recreating generated directory must not rerun CMake'
    }
    $newReference = Join-Path $build 'generated metadata\New.winmd'
    [IO.File]::WriteAllText($newReference, 'new synthetic metadata')
    $before = Count $mergeLog
    Build
    if ($mode -eq 'explicit') {
        Assert ((Count $configureLog) -eq $settledConfigureCount) 'New unlisted generated WinMD must not rerun CMake'
        Assert ((Count $mergeLog) -eq $before) 'Explicit mode must not consume unlisted dependencies'
    } else {
        Assert ((Count $configureLog) -gt $settledConfigureCount) 'Directory-only mode must discover new metadata'
        Assert ((Count $mergeLog) -eq ($before + 1)) 'Directory-only mode must merge newly discovered metadata'
        $before = Count $mergeLog
        Touch $newReference
        Build
        Assert ((Count $mergeLog) -eq ($before + 1)) 'Discovered metadata must remain a file prerequisite'
    }
    $before = Count $mergeLog
    $configureCount = Count $configureLog
    Build
    Assert ((Count $mergeLog) -eq $before) "$mode final build must be no-op"
    Assert ((Count $configureLog) -eq $configureCount) "$mode final build must not rerun CMake"
    "PASS: $mode metadata dependency scheduling"
}
exit 0

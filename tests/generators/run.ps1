# Copyright (c) Microsoft Corporation. All rights reserved.
param(
    [Parameter(Mandatory)] [string] $CMake,
    [Parameter(Mandatory)] [string] $Ninja,
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'build with spaces')
)
$ErrorActionPreference = 'Stop'
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null
$tool = Join-Path $BuildDirectory 'fake tool.exe'
if (-not (Test-Path $tool) -or (Get-Item (Join-Path $PSScriptRoot 'fake_tool.cs')).LastWriteTime -gt (Get-Item $tool).LastWriteTime) {
    # Windows PowerShell's built-in Add-Type creates a native argv-preserving
    # .NET Framework console launcher without Visual Studio or SDK discovery.
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare_tool.ps1') -Output $tool
    if ($LASTEXITCODE -ne 0) { throw 'Fake tool preparation failed' }
}
Get-ChildItem -LiteralPath $BuildDirectory -Filter '*.jsonl' | Remove-Item
(Get-Item -LiteralPath $tool).LastWriteTime = Get-Date
function RunCMake([string[]] $arguments) {
    $output = & $CMake @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
}
function Assert([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}
function Count([string] $name) {
    $path = Join-Path $BuildDirectory "$name.jsonl"
    if (Test-Path $path) { return @(Get-Content $path).Count }
    return 0
}
function Arguments([string] $name) {
    return @(Get-Content (Join-Path $BuildDirectory "$name.jsonl") -Tail 1 | ConvertFrom-Json)
}
function Build { RunCMake @('--build', $BuildDirectory) }
function Touch([string] $path) {
    Start-Sleep -Milliseconds 1100
    (Get-Item -LiteralPath $path).LastWriteTime = Get-Date
}
RunCMake @('-S', $PSScriptRoot, '-B', $BuildDirectory, '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$Ninja", '-DSHRINK_OUTPUTS=OFF')
Build
Assert ((Count 'midl') -eq 1) 'First IDL generation must run once'
Assert ((Arguments 'midl') -contains '/winrt') 'WinRT driver flag must be direct'
$midlArguments = Arguments 'midl'
$metadataIndex = [Array]::IndexOf($midlArguments, '/metadata_dir')
Assert (($metadataIndex -ge 0) -and ($midlArguments[$metadataIndex + 1] -eq (Join-Path $BuildDirectory 'references'))) 'Structured metadata directory must use native path spelling'
Assert ((Arguments 'midl') -contains (Join-Path $BuildDirectory 'include with spaces').Replace('\', '/')) 'Include path must remain one argument'
$custom = Arguments 'midl-custom'
Assert (($custom -contains '/winrt') -and -not ($custom -contains '/nologo')) 'NO_DEFAULT_ARGS must preserve only explicit flags'
$merge = Arguments 'merge'
Assert (($merge -contains '-n:3') -and (@($merge | Where-Object { $_ -eq '-metadata_dir' }).Count -eq 2)) 'Merge depth and duplicate directory order'
$default = Arguments 'default-merge'
Assert (-not (@($default | Where-Object { $_ -like '-n:*' }).Count) -and -not ($default -contains '-partial')) 'Default depth and NO_PARTIAL'
Assert ((Arguments 'zero-merge') -contains '-n:0') 'Explicit zero merge depth must not become the default'
$component = Arguments 'component'
Assert (($component -contains '-pch') -and ($component -contains '-optimize')) 'Component PCH and optimization'
$bare = Arguments 'bare'
Assert (($bare -contains '-comp') -and -not ($bare -contains '-pch') -and -not ($bare -contains '-optimize')) 'Bare component without PCH or optimization'
$root = Join-Path $BuildDirectory 'outputs with spaces'
[xml] $empty = Get-Content (Join-Path $root 'empty.pri.xml') -Raw
Assert (($empty.resources.index.root -eq '\') -and @($empty.resources.index.'indexer-config').Count -eq 1) 'Empty PRI profile'
[xml] $resource = Get-Content (Join-Path $root 'resources.pri.xml') -Raw
Assert (@($resource.resources.index.'indexer-config').Count -eq 4) 'Resource PRI profile'
Assert ($resource.resources.index.'indexer-config'[0].initialPath -eq 'Contoso') 'Resource initial path'
Assert ($resource.resources.index.'indexer-config'[0].convertDotsToSlashes -eq 'true') 'Dotted RESW conversion'
Assert ($resource.resources.index.startIndexAt -notmatch '/') 'Resource manifest path must use native spelling'
$resourceEntries = @(Get-Content (Join-Path $root 'resources.pri.resfiles'))
Assert ($resourceEntries -contains (Join-Path $BuildDirectory 'strings.resw')) 'Relative resource entry must resolve against DIRECTORY to its absolute native path'
[xml] $native = Get-Content (Join-Path $root 'native.pri.xml') -Raw
Assert (@($native.resources.index.'indexer-config' | Where-Object type -eq 'EMBEDFILES').Count -eq 1) 'Original native PRI mode'
Assert ((Get-Content (Join-Path $root 'provider\XamlMetaDataProvider.idl') -Raw) -match 'namespace Contoso') 'Provider must not use ambient namespace'
$counts = @{}
foreach ($name in @('midl', 'midl-custom', 'merge', 'default-merge', 'zero-merge', 'component', 'bare', 'empty', 'resources', 'native', 'custom')) {
    $counts[$name] = Count $name
}
Build
foreach ($name in $counts.Keys) {
    Assert ((Count $name) -eq $counts[$name]) "Second build must be no-op: $name"
}
foreach ($input in @('import.idl', 'options.txt', 'references\Contoso.Reference.winmd', 'fake tool.exe')) {
    $before = Count 'midl'
    $toolCounts = @{}
    if ($input -eq 'fake tool.exe') {
        foreach ($name in $counts.Keys) { $toolCounts[$name] = Count $name }
    }
    Touch (Join-Path $BuildDirectory $input)
    Build
    Assert ((Count 'midl') -eq ($before + 1)) "IDL dependency did not invalidate: $input"
    foreach ($name in $toolCounts.Keys) {
        Assert ((Count $name) -eq ($toolCounts[$name] + 1)) "Tool dependency did not invalidate: $name"
    }
}
$before = Count 'custom'
Touch (Join-Path $BuildDirectory 'custom.xml')
Build
Assert ((Count 'custom') -eq ($before + 1)) 'Explicit PRI config dependency'
foreach ($output in @('component\Contoso.g.h', 'component\sources\Contoso.h', 'component\module.g.cpp')) {
    $before = Count 'component'
    Remove-Item -LiteralPath (Join-Path $root $output)
    Build
    Assert ((Count 'component') -eq ($before + 1)) "Missing output did not regenerate: $output"
}
$before = Count 'merge'
Remove-Item -LiteralPath (Join-Path $root 'merged\Tailspin.winmd')
Build
Assert ((Count 'merge') -eq ($before + 1)) 'Missing additional merge output'
$unlisted = Join-Path $root 'merged\Unlisted.winmd'
$outside = Join-Path $BuildDirectory 'Outside.winmd'
[IO.File]::WriteAllText($unlisted, 'unowned')
[IO.File]::WriteAllText($outside, 'outside output root')
Add-Content -LiteralPath (Join-Path $root 'merged\.merged.owned-outputs') -Value $outside
RunCMake @('-S', $PSScriptRoot, '-B', $BuildDirectory, '-DSHRINK_OUTPUTS=ON')
Build
Assert (-not (Test-Path (Join-Path $root 'merged\Tailspin.winmd'))) 'Previously owned stale output must be pruned'
Assert ((Test-Path $unlisted) -and (Test-Path $outside)) 'Pruning must preserve unowned and outside-root outputs'
$failureOutput = & $CMake --build $BuildDirectory --target failure 2>&1
Assert ($LASTEXITCODE -ne 0) 'MakePRI failure must propagate through PowerShell and Ninja'
Assert (-not (Test-Path (Join-Path $root 'failure.pri'))) 'Failed generation must not create output'
'PASS: SDK-free generator scheduling and argument contracts'
exit 0

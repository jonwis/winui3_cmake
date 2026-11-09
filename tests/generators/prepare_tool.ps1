# Copyright (c) Microsoft Corporation. All rights reserved.
param([Parameter(Mandatory)] [string] $Output)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output }
Add-Type -Path (Join-Path $PSScriptRoot 'fake_tool.cs') -ReferencedAssemblies System.Web.Extensions `
    -OutputAssembly $Output -OutputType ConsoleApplication

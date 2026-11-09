# Wrapper to deal w/ makepri.exe outputting raw UTF-16
# https://github.com/PowerShell/PowerShell/discussions/17163
$origEncoding = [Console]::OutputEncoding
$exitCode = 1
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $tool = $args[0]
    $toolArgs = @($args | Select-Object -Skip 1)
    $output = (& $tool @toolArgs 2>&1)
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 1
    }
}
finally {
    [Console]::OutputEncoding = $origEncoding
}
# Just 'Write-Host $x' formats weirdly
foreach($x in $output)
{
    Write-Host $x
}
exit $exitCode

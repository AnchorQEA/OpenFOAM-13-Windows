# Compile and exercise only the small native resolver, without an OpenFOAM build.
param([string]$Compiler = 'C:\msys64\ucrt64\bin\g++.exe')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$native = Join-Path $root 'src\OpenFOAM\global\windowsRuntime'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('native-startup-' + [guid]::NewGuid().ToString('N'))
$binary = Join-Path $testRoot 'bundle with spaces\bin'
$caseA = Join-Path $testRoot 'case A'
$caseB = Join-Path $testRoot 'case B'
foreach ($directory in $binary, $caseA, $caseB) { [void][IO.Directory]::CreateDirectory($directory) }
$compilerDirectory = Split-Path -Parent $Compiler
$savedPath = $env:PATH
try {
    $env:PATH = "$compilerDirectory;$savedPath"
    & $Compiler -std=gnu++14 -Wall -Wextra -Werror -shared (Join-Path $native 'windowsRuntime.C') -o "$binary\runtimeProbe.dll" "-Wl,--out-implib,$binary\libruntimeProbe.dll.a"
    if ($LASTEXITCODE -ne 0) { throw "Native resolver DLL compilation failed (exit $LASTEXITCODE)." }
    & $Compiler -std=gnu++14 -Wall -Wextra -Werror "-I$native" (Join-Path $root 'applications\test\windowsRuntime\Test-windowsRuntime.C') "-L$binary" -lruntimeProbe -o "$binary\probe.exe"
    if ($LASTEXITCODE -ne 0) { throw "Native resolver probe compilation failed (exit $LASTEXITCODE)." }
}
finally { $env:PATH = $savedPath }
foreach ($dll in 'libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll') {
    Copy-Item -LiteralPath (Join-Path $compilerDirectory $dll) -Destination $binary
}

$scenarios = @(
    @{ Arguments = @(); Case = $caseA },
    @{ Arguments = @('-case', $caseB); Case = $caseB },
    @{ Arguments = @('-case', '..\case B\'); Case = $caseB },
    @{ Arguments = @('-case', ''); Case = $caseA },
    @{ Arguments = @('-case', $caseB, '-case', $caseA); Case = $caseB },
    @{ Arguments = @('-case'); Case = $caseA; Error = '1' },
    @{ Arguments = @('-case', '-help'); Case = $caseA; Error = '1'; Info = '1' },
    @{ Arguments = @('-libs', '(', '-case', '-version', ')'); Case = $caseA },
    @{ Arguments = @('-libs', '("-case" "-version")', '-h'); Case = $caseA; Info = '1' },
    @{ Arguments = @('quote"inside', 'C:\tail\', '', 'a\\"b', '""', '*'); Case = $caseA }
)
foreach ($flag in '-help', '--help', '-h', '-version', '--version', '-v', '-doc', '-srcDoc') {
    $scenarios += @{ Arguments = @($flag); Case = $caseA; Info = '1' }
}
foreach ($scenario in $scenarios) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $binary 'probe.exe'
    $start.Arguments = ($scenario.Arguments | ForEach-Object {
        '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $start.WorkingDirectory = $caseA
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $start.EnvironmentVariables['TEST_CASE_PATH'] = $scenario.Case.Replace('\', '/')
    $start.EnvironmentVariables['TEST_ETC_PATH'] = (Join-Path (Split-Path $binary) 'OpenFOAM-13\etc').Replace('\', '/')
    $start.EnvironmentVariables['TEST_INFORMATIONAL'] = [string]$scenario.Info
    $start.EnvironmentVariables['TEST_ERROR'] = [string]$scenario.Error
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Native startup probe timed out.' }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $output -notmatch 'NATIVE_STARTUP_OK') {
            throw "Native startup failed: $($start.Arguments) : $output"
        }
    }
    finally { $process.Dispose() }
}
Write-Output "Native startup: $($scenarios.Count) scenarios passed. Artifacts: $testRoot"

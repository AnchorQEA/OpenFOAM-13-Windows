# Focused direct-launch regression. Requires rebuilt OpenFOAM and dummy Pstream.
param(
    [Parameter(Mandatory)][string]$ExecutablePath,
    [Parameter(Mandatory)][string]$OpenFOAMRoot,
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [Parameter(Mandatory)][string]$RuntimeDirectory
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('openfoam-paths-' + [guid]::NewGuid().ToString('N'))
$isolatedHome = Join-Path $testRoot 'home'
[void][IO.Directory]::CreateDirectory($isolatedHome)
Write-Output "Path-test staging: $testRoot"

function ConvertTo-NativeArgument([string]$Value) {
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-StartupCheck {
    param([string]$Executable, [string]$Directory, [string[]]$CommandArguments,
          [hashtable]$Environment = @{}, [string]$Expected = 'FILE_NAME_SPACES_OK',
          [switch]$Failure)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = ($CommandArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in @($start.EnvironmentVariables.Keys)) {
        if ($key -match '^(WM_|FOAM_|OPENFOAM_TEST_|PYTHONHOME$|PYTHONPATH$|_MEIPASS2$)') {
            $start.EnvironmentVariables.Remove($key)
        }
    }
    $start.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $start.EnvironmentVariables['HOME'] = $isolatedHome.Replace('\', '/')
    $start.EnvironmentVariables['USERPROFILE'] = $isolatedHome
    foreach ($key in $Environment.Keys) { $start.EnvironmentVariables[$key] = $Environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw "OpenFOAM startup exceeded 30 seconds: $($start.Arguments)"
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if (($Failure -and $process.ExitCode -eq 0) -or
            (-not $Failure -and $process.ExitCode -ne 0) -or
            $output -notmatch $Expected -or $output -match 'stripInvalid\(') {
            throw "OpenFOAM startup failed (exit $($process.ExitCode)): $($start.Arguments)" + [Environment]::NewLine + $output
        }
    }
    finally { $process.Dispose() }
}

foreach ($relative in 'NoSpaces', 'Program Files\OpenFOAM') {
    $bundle = Join-Path $testRoot $relative
    $binaryDir = Join-Path $bundle 'bin'
    $foamDir = Join-Path $bundle 'OpenFOAM-13'
    $caseA = Join-Path $bundle 'case A'
    $caseB = Join-Path $bundle 'case B'
    $empty = Join-Path $bundle 'empty'
    foreach ($path in $binaryDir, $foamDir, "$caseA\system", "$caseB\system", $empty) {
        [void][IO.Directory]::CreateDirectory($path)
    }
    $executable = Join-Path $binaryDir 'Test-fileNameSpaces.exe'
    Copy-Item -LiteralPath $ExecutablePath -Destination $executable
    Copy-Item -LiteralPath (Join-Path $LibraryDirectory 'libOpenFOAM.dll') -Destination $binaryDir
    Copy-Item -LiteralPath (Join-Path $LibraryDirectory 'dummy\libPstream.dll') -Destination $binaryDir
    foreach ($name in 'libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll', 'libgomp-1.dll', 'zlib1.dll', 'libz-1.dll') {
        $source = Join-Path $RuntimeDirectory $name
        if ($name -ne 'libz-1.dll' -or (Test-Path -LiteralPath $source)) {
            Copy-Item -LiteralPath $source -Destination $binaryDir
        }
    }
    Copy-Item -LiteralPath (Join-Path $OpenFOAMRoot 'etc') -Destination $foamDir -Recurse

    # Diagnose transitive DLL dependencies before testing startup.
    $objdump = Join-Path $RuntimeDirectory 'objdump.exe'
    foreach ($binary in Get-ChildItem -LiteralPath $binaryDir -File) {
        $headers = & $objdump -p $binary.FullName
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $($binary.FullName)" }
        foreach ($line in $headers) {
            if ($line -notmatch '^\s*DLL Name:\s*(.+?)\s*$') { continue }
            $dll = $Matches[1]
            if ($dll -match '^(api-ms-win-|ext-ms-win-)') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $binaryDir $dll)) -and
                -not (Test-Path -LiteralPath (Join-Path "$env:SystemRoot\System32" $dll))) {
                throw "Unbundled import: $($binary.Name) -> $dll"
            }
        }
    }

    $fixture = Join-Path $empty 'input fixture.txt'
    [IO.File]::WriteAllText($fixture, 'OPENFOAM_PATH_FIXTURE' + [Environment]::NewLine)
    $fixture = $fixture.Replace('\', '/')
    $configA = Join-Path $caseA 'system\controlDict'
    $configB = Join-Path $caseB 'system\controlDict'
    [IO.File]::WriteAllText($configA, 'DebugSwitches { fileName 1; }')
    [IO.File]::WriteAllText($configB, 'DebugSwitches { fileName 2; }')
    $expectedB = @{ OPENFOAM_TEST_CASE = $caseB.Replace('\', '/'); OPENFOAM_TEST_REQUIRE_CONTROL = '1' }
    Invoke-StartupCheck $executable $empty @($fixture)
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', $caseB) $expectedB
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', '..\case B\') $expectedB
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', $caseB, '-case', $caseA) $expectedB
    Invoke-StartupCheck $executable $caseB @($fixture) $expectedB
    Invoke-StartupCheck $executable $caseB @($fixture, '-case', '') $expectedB
    Invoke-StartupCheck $executable $caseA @($fixture) @{
        OPENFOAM_TEST_CASE = $caseA.Replace('\', '/'); OPENFOAM_TEST_DEBUG = '1'
    }

    [IO.File]::WriteAllText($configA, 'This is not a valid dictionary {')
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', $caseB) $expectedB
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', $empty) @{
        OPENFOAM_TEST_REQUIRE_CONTROL = '1'
    } -Failure -Expected ('Missing selected controlDict: ' + [regex]::Escape($empty.Replace('\', '/')))
    Invoke-StartupCheck $executable $caseA @($fixture, '-case') -Failure -Expected 'requires an argument'
    Invoke-StartupCheck $executable $caseA @($fixture, '-case', '-noFunctionObjects') -Failure -Expected 'requires an argument'
    foreach ($flag in '-help', '--help', '-h', '-version', '--version', '-v', '-doc', '-srcDoc') {
        Invoke-StartupCheck $executable $caseA @($flag) -Expected 'STARTUP_INFO_OK'
    }
    # A flag-shaped library name inside a list must not become a case selector.
    Invoke-StartupCheck $executable $empty @('-libs', '(', '-case', ')', '-help') -Expected 'STARTUP_INFO_OK'

    # Partial user/site overrides still merge onto the bundled global defaults.
    $userEtc = Join-Path $isolatedHome '.OpenFOAM'
    [void][IO.Directory]::CreateDirectory($userEtc)
    $userControl = Join-Path $userEtc 'controlDict'
    [IO.File]::WriteAllText($userControl, 'DebugSwitches { fileName 1; }')
    Invoke-StartupCheck $executable $empty @($fixture) @{
        OPENFOAM_TEST_DEBUG = '1'; OPENFOAM_TEST_ETC = $userControl.Replace('\', '/')
    }
    [IO.File]::Delete($userControl)
    $siteEtc = Join-Path $bundle 'site\etc'
    [void][IO.Directory]::CreateDirectory($siteEtc)
    $siteControl = Join-Path $siteEtc 'controlDict'
    [IO.File]::WriteAllText($siteControl, 'DebugSwitches { fileName 1; }')
    Invoke-StartupCheck $executable $empty @($fixture) @{
        WM_PROJECT_SITE = (Join-Path $bundle 'site').Replace('\', '/')
        OPENFOAM_TEST_DEBUG = '1'; OPENFOAM_TEST_ETC = $siteControl.Replace('\', '/')
    }
    Invoke-StartupCheck $executable $empty @($fixture) @{ WM_PROJECT_DIR = $foamDir.Replace('\', '/') }
    Write-Output "OPENFOAM_PATHS_OK: $relative"
}

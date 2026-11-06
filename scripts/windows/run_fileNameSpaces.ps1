# Called by run_fileNameSpaces.sh after wmake. No simulation or case is required.
param(
    [Parameter(Mandatory)][string]$ExecutablePath,
    [Parameter(Mandatory)][string]$OpenFOAMRoot,
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [Parameter(Mandatory)][string]$RuntimeDirectory
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('openfoam-paths-' + [guid]::NewGuid().ToString('N'))
Write-Output "Path-test staging: $testRoot"

foreach ($relative in 'NoSpaces', 'Program Files\') {
    $bundle = Join-Path $testRoot $relative
    $binaryDir = Join-Path $bundle 'bin'
    $foamDir = Join-Path $bundle 'OpenFOAM-13'
    $caseDir = Join-Path $bundle 'case'
    $fixture = Join-Path $caseDir $(if ($relative -eq 'NoSpaces') { 'fixture.txt' } else { 'input fixture.txt' })
    [void][IO.Directory]::CreateDirectory($binaryDir)
    [void][IO.Directory]::CreateDirectory($foamDir)
    [void][IO.Directory]::CreateDirectory($caseDir)
    Copy-Item -LiteralPath $ExecutablePath -Destination (Join-Path $binaryDir 'Test-fileNameSpaces.exe')
    Copy-Item -LiteralPath (Join-Path $LibraryDirectory 'libOpenFOAM.dll') -Destination $binaryDir
    Copy-Item -LiteralPath (Join-Path $LibraryDirectory 'dummy\libPstream.dll') -Destination $binaryDir
    foreach ($name in 'libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll', 'libgomp-1.dll', 'zlib1.dll') {
        Copy-Item -LiteralPath (Join-Path $RuntimeDirectory $name) -Destination $binaryDir
    }
    Copy-Item -LiteralPath (Join-Path $OpenFOAMRoot 'etc') -Destination $foamDir -Recurse
    [IO.File]::WriteAllText($fixture, "OPENFOAM_PATH_FIXTURE`n")

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $binaryDir 'Test-fileNameSpaces.exe'
    $startInfo.Arguments = '"' + $fixture.Replace('\', '/') + '"'
    $startInfo.WorkingDirectory = $caseDir
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($key in @($startInfo.EnvironmentVariables.Keys)) {
        if ($key -match '^(WM_|FOAM_|PYTHONHOME$|PYTHONPATH$|_MEIPASS2$)') {
            $startInfo.EnvironmentVariables.Remove($key)
        }
    }
    $environment = @{
        WM_PROJECT = 'OpenFOAM'
        WM_PROJECT_VERSION = '13'
        WM_PROJECT_DIR = $foamDir.Replace('\', '/')
        WM_PROJECT_INST_DIR = $bundle.Replace('\', '/')
        WM_OPTIONS = 'mingw_w64GccDPInt32Opt'
        WM_MPLIB = 'Dummy'
        FOAM_MPI = 'dummy'
        FOAM_ETC = (Join-Path $foamDir 'etc').Replace('\', '/')
        FOAM_LIBBIN = $binaryDir.Replace('\', '/')
        FOAM_USER_LIBBIN = $binaryDir.Replace('\', '/')
        FOAM_APPBIN = $binaryDir.Replace('\', '/')
        FOAM_USER_APPBIN = $binaryDir.Replace('\', '/')
        PATH = "$binaryDir;$env:SystemRoot\System32;$env:SystemRoot"
    }
    foreach ($key in $environment.Keys) {
        $startInfo.EnvironmentVariables[$key] = $environment[$key]
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        Write-Output "Testing: $($startInfo.FileName)"
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'OpenFOAM path test exceeded 30 seconds.'
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        Write-Output $output
        if ($process.ExitCode -ne 0 -or $output -match 'stripInvalid\(' -or
            $output -notmatch '(?m)^FILE_NAME_SPACES_OK\r?$') {
            throw "OpenFOAM path test failed (exit $($process.ExitCode)): $relative"
        }
    }
    finally {
        $process.Dispose()
    }
}
Write-Output 'OPENFOAM_PATHS_OK'

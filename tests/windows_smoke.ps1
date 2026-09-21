param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TempRoot = Join-Path $env:RUNNER_TEMP ('rias-windows-smoke-' + [Guid]::NewGuid().ToString('N'))
$Mock = $null
$Dashboard = $null
$AppProcess = $null

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $TempRoot -Force
    $AppDir = Join-Path $TempRoot 'RobloxIAStudio'
    $Exe = Join-Path $AppDir 'RobloxIAStudio.exe'
    if (-not (Test-Path -LiteralPath $Exe)) { throw 'Executable missing from package.' }

    Write-Host '[1/5] Launching native Windows executable...'
    $AppProcess = Start-Process -FilePath $Exe -WorkingDirectory $AppDir -PassThru
    Start-Sleep -Seconds 5
    $AppProcess.Refresh()
    if ($AppProcess.HasExited) { throw ('Application exited during smoke test with code ' + $AppProcess.ExitCode) }
    $null = $AppProcess.CloseMainWindow()
    if (-not $AppProcess.WaitForExit(5000)) { Stop-Process -Id $AppProcess.Id -Force }
    $AppProcess = $null

    Write-Host '[2/5] Validating Studio plugin XML...'
    [xml]$Plugin = Get-Content -LiteralPath (Join-Path $AppDir 'RobloxIAStudioPlugin.rbxmx') -Raw -Encoding UTF8
    $Source = $Plugin.SelectSingleNode('//ProtectedString[@name="Source"]')
    if (-not $Source -or $Source.InnerText -notmatch 'RIAS_GeneratedWorld') { throw 'Studio plugin source is invalid.' }

    Write-Host '[3/5] Starting deterministic Ollama API double...'
    $MockScript = Join-Path $Root 'tests\mock_ollama.py'
    $Mock = Start-Process -FilePath 'python' -ArgumentList @($MockScript, '--port', '11434') -PassThru -WindowStyle Hidden
    $Ready = $false
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        try {
            $null = Invoke-RestMethod -UseBasicParsing -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
            $Ready = $true
            break
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $Ready) { throw 'Mock Ollama API did not start.' }

    Write-Host '[4/5] Executing packaged diagnostic and engine through cmd.exe...'
    $env:RIAS_NONINTERACTIVE = '1'
    & (Join-Path $AppDir 'TESTER_IA_LOCALE.bat')
    if ($LASTEXITCODE -ne 0) { throw ('Packaged diagnostic failed with code ' + $LASTEXITCODE) }

    Write-Host '[5/5] Starting local dashboard and requesting its API...'
    $DashboardScript = Join-Path $AppDir 'Dashboard\DashboardServer.ps1'
    $Dashboard = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $DashboardScript, '-NoBrowser', '-PortStart', '49160'
    ) -PassThru -WindowStyle Hidden
    $DashboardReady = $false
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        try {
            $Config = Invoke-RestMethod -UseBasicParsing -Uri 'http://127.0.0.1:49160/api/config' -TimeoutSec 2
            if ($null -ne $Config.games) { $DashboardReady = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $DashboardReady) { throw 'Dashboard HTTP server did not answer.' }

    Write-Host 'WINDOWS_SMOKE_OK'
} finally {
    if ($AppProcess -and -not $AppProcess.HasExited) { Stop-Process -Id $AppProcess.Id -Force -ErrorAction SilentlyContinue }
    if ($Dashboard -and -not $Dashboard.HasExited) { Stop-Process -Id $Dashboard.Id -Force -ErrorAction SilentlyContinue }
    if ($Mock -and -not $Mock.HasExited) { Stop-Process -Id $Mock.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

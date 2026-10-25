[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][ValidateSet('Primary', 'Final')][string]$Phase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath (Join-Path $source 'yunzhan_workbench\requirements-windows-cp313.lock'))) {
    throw 'Private source checkout is missing or invalid.'
}

function Invoke-QuietStep {
    param([string]$Name, [string]$Directory, [string]$Program, [string[]]$Arguments)
    $logPath = Join-Path $env:RUNNER_TEMP ([guid]::NewGuid().ToString('N') + '.log')
    Push-Location -LiteralPath $Directory
    try {
        & $Program @Arguments *> $logPath
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            if ($Name -eq 'Python unit tests') {
                $text = Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue
                $safeTypes = @('UnicodeEncodeError', 'UnicodeDecodeError', 'ModuleNotFoundError',
                    'ImportError', 'FileNotFoundError', 'PermissionError', 'AssertionError',
                    'TimeoutExpired', 'OSError', 'RuntimeError', 'TypeError', 'ValueError')
                foreach ($type in $safeTypes) {
                    $count = [regex]::Matches([string]$text, "\b$type\b").Count
                    if ($count -gt 0) { Write-Output "Python test error class $type count $count" }
                }
                if ([string]$text -match 'FAILED \(failures=([0-9]+), errors=([0-9]+)\)') {
                    Write-Output "Python test summary failures=$($Matches[1]) errors=$($Matches[2])"
                } elseif ([string]$text -match 'FAILED \(errors=([0-9]+)\)') {
                    Write-Output "Python test summary errors=$($Matches[1])"
                }
            }
            throw "$Name failed with exit code $exit. Review and reproduce locally; private test output is intentionally not public."
        }
        Write-Output "$Name passed"
    } finally {
        Pop-Location
        if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    }
}

$app = Join-Path $source 'yunzhan_workbench'
$frontend = Join-Path $app 'frontend'
$keywordEngine = Join-Path $app 'keyword_engine'

if ($Phase -eq 'Primary') {
    Invoke-QuietStep 'Tracked-source security' $source 'python' @('yunzhan_workbench/scripts/security_scan.py')
    Invoke-QuietStep 'Install dependency auditor' $source 'python' @('-m', 'pip', 'install', 'pip-audit==2.10.1')
    Invoke-QuietStep 'Python dependency audit' $source 'python' @('-m', 'pip_audit', '-r', 'yunzhan_workbench/requirements-windows-cp313.lock', '--strict')
    Invoke-QuietStep 'Install Python lock' $source 'python' @('-m', 'pip', 'install', '-r', 'yunzhan_workbench/requirements-windows-cp313.lock')
    Invoke-QuietStep 'Python unit tests' $app 'python' @('-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py')
    Invoke-QuietStep 'Collector tests' $source 'node' @(
        '--test',
        'shared/didi-incentive-dashboard/model.test.mjs',
        'chrome_business_collector/helper/otp-utils.test.mjs',
        'chrome_business_collector/jd-secret-agent.test.cjs',
        'chrome_business_collector/jd-secret-worker.test.cjs',
        'chrome_business_collector/service-worker.test.mjs',
        'chrome_business_collector/unified-collector.test.cjs',
        'meituan_official_collector/service-worker.test.cjs'
    )
    Invoke-QuietStep 'Install frontend lock' $frontend 'npm.cmd' @('ci', '--no-audit', '--no-fund')
    Invoke-QuietStep 'Frontend production audit' $frontend 'npm.cmd' @('audit', '--omit=dev', '--audit-level=high')
    Invoke-QuietStep 'Frontend tests' $frontend 'npm.cmd' @('test', '--if-present')
    Invoke-QuietStep 'Frontend build' $frontend 'npm.cmd' @('run', 'build')
    return
}

Invoke-QuietStep 'Install keyword-engine lock' $keywordEngine 'npm.cmd' @('ci', '--omit=dev', '--no-audit', '--no-fund')
Invoke-QuietStep 'Keyword-engine production audit' $keywordEngine 'npm.cmd' @('audit', '--omit=dev', '--audit-level=high')
Invoke-QuietStep 'Keyword-engine bridge tests' $keywordEngine 'node' @('--test', 'server/chrome-bridge.test.mjs')
Invoke-QuietStep 'Code-only release-package check' $source 'python' @('yunzhan_workbench/deploy/prepare_release.py')
foreach ($test in @('test_release_deployer.ps1', 'test_production_backup_scripts.ps1', 'test_data_dashboard_embedding.ps1')) {
    Invoke-QuietStep "Release guard $test" $source 'powershell.exe' @('-NoProfile', '-NonInteractive', '-File', "yunzhan_workbench/tests/$test")
}

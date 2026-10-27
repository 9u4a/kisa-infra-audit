# 03_web/tests/run_tests_iis.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 Windows Server VM, IIS 를 workflow 에서 설치)에서만 실행한다.
# 02_windows/tests/run_tests.ps1 과 같은 구조: 픽스처 적용 → run.ps1(Windows PowerShell 5.1) → 기대값 비교.
# -Bootstrap: 실제 결과를 expected_iis_<mode>.json 으로 저장(기준값 생성용, artifact 로 내려받아 커밋).
param([switch]$Bootstrap)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$fail = $false
foreach ($mode in @("vuln", "hardened")) {
    Write-Host "[*] IIS $mode 픽스처 적용..."
    & (Join-Path $ScriptDir "fixtures\apply_iis.ps1") -Mode $mode

    $outDir = Join-Path $env:TEMP "web03iis_$mode"
    Remove-Item -Recurse -Force $outDir -ErrorAction SilentlyContinue
    & powershell -NoProfile -File (Join-Path $RepoRoot "03_web\run.ps1") -OutBase $outDir *>$null

    $resultPath = Get-ChildItem -Path $outDir -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $resultPath) { Write-Host "FAIL: iis/$mode - result.json 을 찾지 못함"; $fail = $true; continue }
    $actual = @{}
    foreach ($it in (Get-Content -Raw -Encoding UTF8 $resultPath | ConvertFrom-Json).items) { $actual[$it.code] = $it.status }

    $expectedPath = Join-Path $ScriptDir "fixtures\expected_iis_$mode.json"
    if ($Bootstrap) {
        $actual | ConvertTo-Json | Set-Content -Path $expectedPath -Encoding utf8
        Write-Host "BOOTSTRAP: iis/$mode -> $expectedPath"
        (Get-Content -Raw -Encoding UTF8 $resultPath | ConvertFrom-Json).items | ForEach-Object { Write-Host ("  {0,-7} {1,-7} {2}" -f $_.code, $_.status, $_.detail) }
        continue
    }
    if (-not (Test-Path $expectedPath)) { Write-Host "FAIL: iis/$mode - $expectedPath 가 없음(-Bootstrap 필요)"; $fail = $true; continue }
    $expected = Get-Content -Raw $expectedPath | ConvertFrom-Json
    $failures = @()
    foreach ($prop in $expected.PSObject.Properties) {
        if ($actual[$prop.Name] -ne $prop.Value) { $failures += "$($prop.Name): 기대=$($prop.Value) 실제=$($actual[$prop.Name])" }
    }
    if ($failures.Count -gt 0) { Write-Host "FAIL: iis/$mode - $($failures.Count)건 불일치"; $failures | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
    else { Write-Host "PASS: iis/$mode" }
}
if ($fail) { exit 1 }

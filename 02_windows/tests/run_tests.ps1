# 02_windows/tests/run_tests.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다 - 실제 레지스트리를 두 가지 모드로
# 바꾸고 되돌리지 않는다(어차피 VM이 버려짐). 로컬 개발자 PC에서는 절대 실행하지 말 것.
#
# -Bootstrap: 실제 run.ps1 결과를 expected_<mode>.json 으로 저장한다(최초 1회, 기준값 생성용).
# 기본(스위치 없음): 저장된 expected_<mode>.json 과 비교해 PASS/FAIL 을 보고한다.
param([switch]$Bootstrap)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$fail = $false
foreach ($mode in @("vuln", "hardened")) {
    Write-Host "[*] $mode 픽스처 적용..."
    & (Join-Path $ScriptDir "fixtures\apply.ps1") -Mode $mode

    $outDir = Join-Path $env:TEMP "w02test_$mode"
    Remove-Item -Recurse -Force $outDir -ErrorAction SilentlyContinue
    & powershell -NoProfile -File (Join-Path $RepoRoot "02_windows\run.ps1") -OutBase $outDir *>$null

    $resultPath = Get-ChildItem -Path $outDir -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $resultPath) {
        Write-Host "FAIL: $mode - result.json 을 찾지 못함"
        $fail = $true
        continue
    }
    $actualItems = (Get-Content -Raw $resultPath | ConvertFrom-Json).items
    $actual = @{}
    foreach ($it in $actualItems) { $actual[$it.code] = $it.status }

    $expectedPath = Join-Path $ScriptDir "fixtures\expected_$mode.json"
    if ($Bootstrap) {
        $actual | ConvertTo-Json | Set-Content -Path $expectedPath -Encoding utf8
        Write-Host "BOOTSTRAP: $mode -> $expectedPath 에 저장함"
        continue
    }

    if (-not (Test-Path $expectedPath)) {
        Write-Host "FAIL: $mode - $expectedPath 가 없음(먼저 -Bootstrap 으로 생성 필요)"
        $fail = $true
        continue
    }
    $expected = Get-Content -Raw $expectedPath | ConvertFrom-Json
    $failures = @()
    foreach ($prop in $expected.PSObject.Properties) {
        $code = $prop.Name
        $expectedStatus = $prop.Value
        $actualStatus = $actual[$code]
        if ($actualStatus -ne $expectedStatus) {
            $failures += "$code`: 기대=$expectedStatus 실제=$actualStatus"
        }
    }
    if ($failures.Count -gt 0) {
        Write-Host "FAIL: $mode - $($failures.Count)건 불일치"
        $failures | ForEach-Object { Write-Host "  - $_" }
        $fail = $true
    } else {
        Write-Host "PASS: $mode"
    }
}

if ($fail) { exit 1 }

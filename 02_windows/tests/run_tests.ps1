# 02_windows/tests/run_tests.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다 - 실제 레지스트리를 두 가지 모드로
# 바꾸고 되돌리지 않는다(어차피 VM이 버려짐). 로컬 개발자 PC에서는 절대 실행하지 말 것.
#
# 기본: 저장된 expected_<mode>.json 과 비교해 PASS/FAIL 을 보고한다.
# -Bootstrap: 실제 결과와 expected_<mode>.json 의 차이만 출력한다(파일을 쓰지 않음, 항상 exit 0). 1.4.0 부터 기대값은 도구 출력이
#   아니라 가이드 판단 기준 + 픽스처 상태로 정한다 - 예전처럼 도구 결과를 그대로 저장하면 오판이 "정답"으로 굳는다(X-08).
#   항목별 양방향 검증은 tests/fixtures/cases/(02_windows/tests/case_runner.ps1)가 맡는다.
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
        $exp = if (Test-Path $expectedPath) { Get-Content -Raw $expectedPath | ConvertFrom-Json } else { $null }
        $diff = @(foreach ($k in ($actual.Keys | Sort-Object)) { $e = if ($exp) { $exp.$k } else { $null }; if ($e -ne $actual[$k]) { "$k`: 기대=$e 실제=$($actual[$k])" } })
        Write-Host "BOOTSTRAP(차이만 출력, 파일 미변경): $mode - $($diff.Count)건"
        $diff | ForEach-Object { Write-Host "  - $_" }
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

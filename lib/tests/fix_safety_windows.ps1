# lib/tests/fix_safety_windows.ps1 -Category <02_windows|07_pc|03_web>
# Windows 계열 조치(fix.ps1)의 운영 안전 회귀 테스트. GitHub Actions windows-latest(휘발성 Windows Server
# VM)에서만 실행한다 - 실제 보안 정책·레지스트리·서비스·IIS 설정을 바꾼다. 로컬 개발자 PC에서는 실행 금지.
#   ① 진단 → ② fix.ps1 -Apply -Yes(비대화형: confirm 등급은 확인 단계에서 건너뜀, auto 만 적용)
#   → ③ 재진단: 적용된 항목이 VULN/ERROR 를 벗어났는가 → ④ fix.ps1 -Rollback
#   → ⑤ 재진단: 적용된 항목의 판정이 조치 전과 같은가(원복 불가로 보고된 항목은 경고로만 표시)
# 확인 질문은 파이프 입력으로 비대화형을 만들어(Test-FixInteractive) CI 가 입력 대기로 멈추지 않게 한다.
param([Parameter(Mandatory = $true)][ValidateSet("02_windows", "07_pc", "03_web")][string]$Category)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$runPs1 = Join-Path $Repo "$Category\run.ps1"
$fixPs1 = Join-Path $Repo "$Category\fix.ps1"

function Invoke-Diag([string]$Tag) {
    $out = Join-Path $env:TEMP "fs_${Category}_$Tag"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    & powershell -NoProfile -NonInteractive -File $runPs1 -OutBase $out *>$null
    $path = Get-ChildItem -Path $out -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { throw "$Tag 진단 결과(result.json)를 찾지 못함" }
    $map = @{}
    foreach ($it in (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json).items) { $map[$it.code] = $it.status }
    return @{ Path = $path; Map = $map }
}

$fail = @()
$base = Invoke-Diag "base"

$fixOut = Join-Path $env:TEMP "fs_${Category}_fix"
Remove-Item -Recurse -Force $fixOut -ErrorAction SilentlyContinue
$applyLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -ResultJson $base.Path -OutBase $fixOut -Apply -Yes 2>&1 | Out-String
$runDir = Get-ChildItem -Path $fixOut -Directory | Select-Object -First 1 -ExpandProperty FullName
if (-not $runDir) { throw "조치 출력 폴더를 찾지 못함:`n$applyLog" }
$logLines = Get-Content -Encoding UTF8 (Join-Path $runDir "changes.log") | Where-Object { $_ -and -not $_.StartsWith("#") }
$rows = $logLines | ForEach-Object { $c = $_ -split "`t"; [PSCustomObject]@{ Code = $c[1]; Grade = $c[2]; Result = $c[3]; Detail = ($c[4..($c.Count - 1)] -join " ") } }
$applied = @($rows | Where-Object Result -eq "APPLIED" | ForEach-Object Code)
Write-Host "[$Category] 적용 결과: " (($rows | Group-Object Result | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", ")
$rows | Where-Object { $_.Result -like "FAILED*" -or $_.Result -eq "ABORTED" } | ForEach-Object { Write-Host "  $($_.Code) $($_.Result): $($_.Detail)" }
if ($applyLog -match '\[백업 실패\]' -or ($rows | Where-Object Result -eq "ABORTED")) { $fail += "백업 실패로 중단됨" }
if ($rows | Where-Object Result -eq "FAILED_NOT_ROLLED_BACK") { $fail += "적용 실패 후 되돌리지 못한 항목 있음" }
if ($applied.Count -eq 0) { Write-Host "  (auto 등급으로 적용된 항목 없음 - 이후 비교 생략)" }

$after = Invoke-Diag "after"
foreach ($c in $applied) {
    if ($after.Map[$c] -in @("VULN", "ERROR")) { $fail += "${c}: 적용 후에도 $($after.Map[$c])" }
}

$rbLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -Rollback $runDir 2>&1 | Out-String
$noRb = @([regex]::Matches($rbLog, '원복 일부 실패/불가: (\S+)') | ForEach-Object { $_.Groups[1].Value })
$rb = Invoke-Diag "rollback"
foreach ($c in $applied) {
    if ($rb.Map[$c] -ne $base.Map[$c]) {
        if ($noRb -contains $c) { Write-Host "  경고: ${c} 원복 불가로 보고됨(조치 전 $($base.Map[$c]) → 원복 후 $($rb.Map[$c]))" }
        else { $fail += "${c}: 원복 후 판정이 조치 전과 다름(전 $($base.Map[$c]) / 후 $($rb.Map[$c]))" }
    }
}
if ($noRb.Count -gt 0) { Write-Host "  원복 불가로 보고된 항목: $($noRb -join ', ')" }

if ($fail.Count -gt 0) {
    Write-Host "FAIL: $Category/fix-safety"; $fail | ForEach-Object { Write-Host "  - $_" }
    Write-Host "----- apply log -----"; Write-Host $applyLog; Write-Host "----- rollback log -----"; Write-Host $rbLog
    exit 1
}
Write-Host "PASS: $Category/fix-safety (적용 $($applied.Count)건: $($applied -join ', '))"

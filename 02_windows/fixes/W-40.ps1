# W-40 (중) 정책에 따른 시스템 로깅 설정 [fix: auto]
# checks/W-40.ps1 과 동일한 5개 하위 범주를 성공/실패 모두 감사하도록 설정한다(각 범주의
# Need 기준이 "Failure"만 요구하는 경우도 있으나 "Success and Failure"가 상위 호환이다).
# auditpol 설정은 레지스트리가 아닌 감사 정책 저장소(SecEdit 와 별도)에 저장되어 표준
# 레지스트리 헬퍼로 백업할 수 없다 - 변경 전 상태를 changes.log 증적에만 남기고, 표준
# Restore-FixItem 원복 대상에는 포함하지 않는다(02_windows/CLAUDE.md 참고).

$subcats = @(
    "{0CCE923A-69AE-11D9-BED3-505054503030}",
    "{0CCE923F-69AE-11D9-BED3-505054503030}",
    "{0CCE9228-69AE-11D9-BED3-505054503030}",
    "{0CCE9215-69AE-11D9-BED3-505054503030}",
    "{0CCE922F-69AE-11D9-BED3-505054503030}"
)

$before = @()
foreach ($g in $subcats) {
    $before += (& auditpol.exe /get /subcategory:"$g" /r 2>$null | Where-Object { $_ -like "*$g*" } | Select-Object -First 1)
}

$failed = @()
foreach ($g in $subcats) {
    & auditpol.exe /set /subcategory:"$g" /success:enable /failure:enable 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += $g }
}

if ($failed.Count -eq 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "5개 감사 하위 범주를 성공/실패 모두 감사하도록 설정함"
    $Global:FixEvidence = "변경 전:`n" + ($before -join "`n")
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 감사 하위 범주 설정 실패: $($failed -join ', ')"
    $Global:FixEvidence = ""
}

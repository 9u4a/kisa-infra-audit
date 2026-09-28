# W-37 (중) 예약된 작업에 의심스러운 명령이 등록되어 있는지 점검
# 판단 기준(가이드 원문): 양호 = 예약 작업을 주기적으로 점검하고 불필요한 작업을 제거한 경우
#                        취약 = 점검하지 않거나 제거하지 않은 경우
# "의심스러움"은 기계적으로 판단할 수 없으므로, Microsoft 기본 제공 경로(\Microsoft\Windows\*)를
# 제외한 사용자 정의 예약 작업 목록을 근거로 제시하고 MANUAL 로 응답한다.

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike "\Microsoft\Windows\*" -and $_.State -ne "Disabled" }
} catch {
    return New-CheckResult -Code "W-37" -Status "ERROR" -Detail "Get-ScheduledTask 실행 실패: $($_.Exception.Message)"
}

if (-not $tasks -or $tasks.Count -eq 0) {
    return New-CheckResult -Code "W-37" -Status "GOOD" -Detail "Microsoft 기본 제공 경로 외의 활성 예약 작업이 없음"
}

$evidence = $tasks | ForEach-Object {
    $action = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join "; "
    "$($_.TaskPath)$($_.TaskName) [$($_.State)] -> $action"
}

return New-CheckResult -Code "W-37" -Status "MANUAL" `
    -Detail "Microsoft 기본 경로 외의 활성 예약 작업이 $($tasks.Count)건 존재함 — 의심스러운 명령/파일 여부를 수동 검토 필요" `
    -Evidence ($evidence -join "`n")

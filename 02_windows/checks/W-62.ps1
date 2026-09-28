# W-62 (중) 시작 프로그램 목록 분석
# 판단 기준(가이드 원문): 양호 = 시작 프로그램을 정기적으로 검사하고 불필요한 항목을 비활성화
#                        취약 = 정기 검사 미실시 및 불필요한 프로그램 방치
# "정기적 검사 여부"는 운영 절차이므로 자동 판정이 불가능하다. 현재 등록된 시작 프로그램 목록을
# 근거로 제시하고 MANUAL 로 응답한다.

try {
    $items = Get-CimInstance Win32_StartupCommand -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-62" -Status "ERROR" -Detail "시작 프로그램 목록 조회 실패: $($_.Exception.Message)"
}

if (-not $items -or $items.Count -eq 0) {
    return New-CheckResult -Code "W-62" -Status "GOOD" -Detail "등록된 시작 프로그램이 없음"
}

$evidence = $items | ForEach-Object { "$($_.Name) | $($_.Command) | $($_.Location)" }

return New-CheckResult -Code "W-62" -Status "MANUAL" `
    -Detail "시작 프로그램이 $($items.Count)건 등록되어 있음 — 정기 검사 절차 존재 여부 및 불필요/의심스러운 항목은 수동 검토 필요" `
    -Evidence ($evidence -join "`n")

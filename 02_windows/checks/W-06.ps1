# W-06 (상) 관리자 그룹에 최소한의 사용자 포함
# 판단 기준(가이드 원문): 양호 = Administrators 그룹 구성원 1명 이하이거나 불필요한 계정 없음
#                        취약 = 불필요한 관리자 계정이 존재하는 경우
# "불필요" 여부는 조직 판단이 필요하지만, "1명 이하"는 객관적으로 자동 판정 가능하다.

try {
    $members = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-06" -Status "ERROR" -Detail "Administrators 그룹 구성원 조회 실패: $($_.Exception.Message)"
}

$evidence = ($members | ForEach-Object { "$($_.Name) ($($_.ObjectClass))" }) -join "`n"

if ($members.Count -le 1) {
    return New-CheckResult -Code "W-06" -Status "GOOD" -Detail "Administrators 그룹 구성원이 $($members.Count)명으로 최소 인원 기준을 충족함" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-06" -Status "MANUAL" -Detail "Administrators 그룹 구성원이 $($members.Count)명 — 각 계정의 관리 업무 필요성을 수동 검토 필요" -Evidence $evidence
}

# W-06 (상) 관리자 그룹에 최소한의 사용자 포함
# 판단 기준(가이드 원문): 양호 = Administrators 그룹 구성원 1명 이하이거나 불필요한 계정 없음
#                        취약 = 불필요한 관리자 계정이 존재하는 경우
# "불필요" 여부는 조직 판단이 필요하지만, "1명 이하"는 객관적으로 자동 판정 가능하다.
# W-R9: 그룹은 SID(S-1-5-32-544)로 조회한다(비영문 OS 에서는 "Administrators" 이름이 번역돼 조회 실패).
# W-R15: 구성원 1명이 그룹(예: Domain Admins)이면 실제 관리자는 여러 명일 수 있어 GOOD 으로 단정하지 않는다.

try {
    $members = Get-LocalGroupMembersBySid -Sid 'S-1-5-32-544'
} catch {
    return New-CheckResult -Code "W-06" -Status "ERROR" -Detail "Administrators 그룹 구성원 조회 실패: $($_.Exception.Message)"
}

$evidence = ($members | ForEach-Object { "$($_.Name) ($($_.ObjectClass)) $($_.SID)" }) -join "`n"
$groups = @($members | Where-Object { $_.ObjectClass -notmatch '^User$' })

if ($members.Count -le 1 -and $groups.Count -eq 0) {
    return New-CheckResult -Code "W-06" -Status "GOOD" -Detail "Administrators 그룹 구성원이 $($members.Count)명으로 최소 인원 기준을 충족함" -Evidence $evidence
} elseif ($members.Count -le 1) {
    return New-CheckResult -Code "W-06" -Status "MANUAL" -Detail "Administrators 그룹 구성원이 그룹($($groups[0].Name))이라 실제 관리자 수를 확인할 수 없음 — 그룹 구성원을 수동 검토 필요" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-06" -Status "MANUAL" -Detail "Administrators 그룹 구성원이 $($members.Count)명 — 각 계정의 관리 업무 필요성을 수동 검토 필요" -Evidence $evidence
}

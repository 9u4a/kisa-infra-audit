# W-14 (중) 원격터미널 접속 가능한 사용자 그룹 제한
# 판단 기준(가이드 원문): 양호 = 관리자 계정 외 별도 계정을 생성해 원격 접속 사용자 그룹에 등록,
#                        불필요한 계정 없음 / 취약 = 별도 계정이 존재하지 않는 경우

try {
    $members = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction Stop
} catch {
    # 그룹이 없거나(RDP 미사용) 조회 실패
    return New-CheckResult -Code "W-14" -Status "NA" -Detail "Remote Desktop Users 그룹을 조회할 수 없음 (원격 데스크톱 미사용 가능성)"
}

$evidence = ($members | ForEach-Object { "$($_.Name) ($($_.ObjectClass))" }) -join "`n"

if ($members.Count -gt 0) {
    return New-CheckResult -Code "W-14" -Status "GOOD" -Detail "Remote Desktop Users 그룹에 원격 접속용 별도 계정이 등록되어 있음 ($($members.Count)명) — 각 계정 필요성은 수동 재확인 권장" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-14" -Status "VULN" -Detail "Remote Desktop Users 그룹에 등록된 별도 계정이 없음 (관리자 계정 외 원격 접속 계정 미구성)" -Evidence "구성원 없음"
}

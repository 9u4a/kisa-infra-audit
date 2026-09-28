# W-11 (중) 로컬 로그온 허용
# 판단 기준(가이드 원문): 양호 = 로컬 로그온 허용 정책에 Administrators, IUSR_ 만 존재
#                        취약 = 그 외 계정/그룹이 존재하는 경우

$accounts = Get-SecPrivilegeAccounts -Right "SeInteractiveLogonRight"
if ($accounts.Count -eq 0) {
    return New-CheckResult -Code "W-11" -Status "MANUAL" -Detail "SeInteractiveLogonRight 조회 결과가 없음 — secedit 값 확인 필요"
}

$extra = $accounts | Where-Object { $_ -notmatch "Administrators$" -and $_ -notmatch "IUSR" }
$evidence = $accounts -join "`n"

if ($extra.Count -eq 0) {
    return New-CheckResult -Code "W-11" -Status "GOOD" -Detail "로컬 로그온 허용 정책에 Administrators/IUSR_ 외 계정이 없음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-11" -Status "VULN" -Detail ("로컬 로그온 허용 정책에 불필요한 계정/그룹 존재: " + ($extra -join ", ")) -Evidence $evidence
}

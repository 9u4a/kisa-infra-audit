# W-49 (상) 원격 시스템에서 강제로 시스템 종료
# 판단 기준(가이드 원문): 양호 = 정책에 "Administrators"만 존재 / 취약 = 그 외 계정/그룹 존재

$accounts = Get-SecPrivilegeAccounts -Right "SeRemoteShutdownPrivilege"
$evidence = $accounts -join "`n"

if ($accounts.Count -eq 0) {
    return New-CheckResult -Code "W-49" -Status "VULN" -Detail "SeRemoteShutdownPrivilege 가 설정되어 있지 않음(비정상)" -Evidence "없음"
}

$extra = $accounts | Where-Object { $_ -notmatch "Administrators$" }
if ($extra.Count -eq 0) {
    return New-CheckResult -Code "W-49" -Status "GOOD" -Detail "원격 시스템 종료 정책에 Administrators 만 존재함" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-49" -Status "VULN" -Detail ("원격 시스템 종료 정책에 Administrators 외 계정/그룹 존재: " + ($extra -join ", ")) -Evidence $evidence
}

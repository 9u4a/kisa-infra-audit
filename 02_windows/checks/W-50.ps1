# W-50 (상) 보안 감사를 로그 할 수 없는 경우 즉시 시스템 종료
# 판단 기준(가이드 원문): 양호 = 정책이 "사용 안 함"(CrashOnAuditFail=0 또는 미설정)
#                        취약 = "사용"(1 이상)

$val = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "CrashOnAuditFail"

if (-not $val -or $val -eq 0) {
    return New-CheckResult -Code "W-50" -Status "GOOD" -Detail "보안 감사 로그 실패 시 시스템 종료 정책이 사용 안 함으로 설정됨(또는 미설정)" -Evidence "CrashOnAuditFail=$val"
} else {
    return New-CheckResult -Code "W-50" -Status "VULN" -Detail "보안 감사 로그 실패 시 시스템 종료 정책이 사용으로 설정됨" -Evidence "CrashOnAuditFail=$val"
}

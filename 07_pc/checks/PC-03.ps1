# PC-03 (중) 복구 콘솔에서 자동 로그온을 금지하도록 설정
# 판단 기준(가이드 원문): 양호 = "복구 콘솔 자동 로그온 허용"이 사용 안 함(0)
#                        취약 = 사용(1)
# 참고: 가이드 원문에도 "설정하지 않았다면 레지스트리가 존재하지 않으며 이 경우 비활성화(양호)"로 명시됨

$val = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole" -Name "SecurityLevel"

if ($null -eq $val -or $val -eq 0) {
    return New-CheckResult -Code "PC-03" -Status "GOOD" -Detail "복구 콘솔 자동 로그온 허용이 설정되어 있지 않거나 사용 안 함임" -Evidence "SecurityLevel=$val"
} else {
    return New-CheckResult -Code "PC-03" -Status "VULN" -Detail "복구 콘솔 자동 로그온 허용이 사용으로 설정됨" -Evidence "SecurityLevel=$val"
}

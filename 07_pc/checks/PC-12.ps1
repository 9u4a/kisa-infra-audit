# PC-12 (중) Windows 자동 로그인 점검
# 판단 기준(가이드 원문): 양호 = AutoAdminLogon 이 비활성화된 경우 / 취약 = 활성화된 경우
# 참고: 가이드 원문에도 "설정한 적 없으면 레지스트리가 존재하지 않으며 이 경우 비활성화(양호)"로 명시됨

$val = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon"

if ($null -eq $val -or $val -eq "0" -or $val -eq 0) {
    return New-CheckResult -Code "PC-12" -Status "GOOD" -Detail "AutoAdminLogon 이 설정되어 있지 않거나 0 임 (자동 로그인 비활성화)" -Evidence "AutoAdminLogon=$val"
} else {
    return New-CheckResult -Code "PC-12" -Status "VULN" -Detail "AutoAdminLogon 이 1로 설정되어 자동 로그인이 활성화되어 있음" -Evidence "AutoAdminLogon=$val"
}

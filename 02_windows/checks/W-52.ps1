# W-52 (상) Autologon 기능 제어
# 판단 기준(가이드 원문): 양호 = AutoAdminLogon 값이 없거나 0 / 취약 = 1
# 참고: 가이드 원문에도 "AutoAdminLogon 키가 없는 경우 기본값 비활성화" 로 명시됨

$val = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon"

if ($null -eq $val -or $val -eq "0" -or $val -eq 0) {
    return New-CheckResult -Code "W-52" -Status "GOOD" -Detail "AutoAdminLogon 이 설정되어 있지 않거나 0 임" -Evidence "AutoAdminLogon=$val"
} else {
    return New-CheckResult -Code "W-52" -Status "VULN" -Detail "AutoAdminLogon 이 1로 설정되어 자동 로그인이 활성화되어 있음" -Evidence "AutoAdminLogon=$val"
}

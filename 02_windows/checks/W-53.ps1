# W-53 (상) 이동식 미디어 포맷 및 꺼내기 허용
# 판단 기준(가이드 원문): 양호 = 정책이 "Administrators" 로만 설정된 경우
#                        취약 = Administrators 외에도 허용된 경우
# AllocateDASD: 0=Administrators, 1=Administrators+Power Users, 2=Administrators+Interactive Users
# Windows Vista 이후 UI 에서 제거된 레거시 기능으로, 키가 없으면 제한 없음(Administrators 전용)이
# 기본 동작이라 GOOD 으로 간주한다.

$val = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AllocateDASD"

if ($null -eq $val -or $val -eq "0" -or $val -eq 0) {
    return New-CheckResult -Code "W-53" -Status "GOOD" -Detail "이동식 미디어 포맷/꺼내기가 Administrators 로 제한되어 있음(또는 미설정 기본값)" -Evidence "AllocateDASD=$val"
} else {
    return New-CheckResult -Code "W-53" -Status "VULN" -Detail "이동식 미디어 포맷/꺼내기가 Administrators 외 사용자에게도 허용됨" -Evidence "AllocateDASD=$val"
}

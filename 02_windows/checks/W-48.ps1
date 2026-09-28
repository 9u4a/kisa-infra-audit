# W-48 (상) 로그온하지 않고 시스템 종료 허용
# 판단 기준(가이드 원문): 양호 = "사용 안 함"(레지스트리 ShutdownWithoutLogon=0)
#                        취약 = "사용"(1)

$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$val = Test-RegistryValue -Path $path -Name "ShutdownWithoutLogon"

# 주의: Windows 기본값은 1(사용/취약)이다 — 값이 없다고 안전한 쪽으로 단정하지 않는다.
if ($val -eq 0) {
    return New-CheckResult -Code "W-48" -Status "GOOD" -Detail "로그온하지 않고 시스템 종료 허용 정책이 사용 안 함으로 설정됨" -Evidence "$path!ShutdownWithoutLogon=$val"
} else {
    return New-CheckResult -Code "W-48" -Status "VULN" -Detail "로그온하지 않고 시스템 종료 허용 정책이 사용으로 설정됨(기본값 포함)" -Evidence "$path!ShutdownWithoutLogon=$val"
}

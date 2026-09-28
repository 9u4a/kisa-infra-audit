# W-13 (중) 콘솔 로그온 시 로컬 계정에서 빈 암호 사용 제한
# 판단 기준(가이드 원문): 양호 = 정책이 "사용"(레지스트리 LimitBlankPasswordUse=1)
#                        취약 = "사용 안 함"(0)

$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$val = Test-RegistryValue -Path $path -Name "LimitBlankPasswordUse"

if ($val -eq 1 -or $null -eq $val) {
    # 레지스트리 값이 없는 경우 Windows 기본값은 1(제한함, 안전)
    return New-CheckResult -Code "W-13" -Status "GOOD" -Detail "콘솔 로그온 시 빈 암호 사용 제한 정책이 사용으로 설정됨(또는 기본값)" -Evidence "$path!LimitBlankPasswordUse=$val"
} else {
    return New-CheckResult -Code "W-13" -Status "VULN" -Detail "콘솔 로그온 시 빈 암호 사용 제한 정책이 사용 안 함으로 설정됨" -Evidence "$path!LimitBlankPasswordUse=$val"
}

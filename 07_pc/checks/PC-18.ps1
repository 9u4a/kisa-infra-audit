# PC-18 (중) 원격 지원을 금지하도록 정책이 설정
# 판단 기준(가이드 원문): 양호 = 원격 지원이 "사용 안 함"(0) / 취약 = "사용"(1, 기본값)

$val = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp"

# Windows 클라이언트 기본값은 1(사용/취약)이므로 미설정을 안전하다고 가정하지 않는다.
if ($val -eq 0) {
    return New-CheckResult -Code "PC-18" -Status "GOOD" -Detail "원격 지원이 사용 안 함으로 설정됨" -Evidence "fAllowToGetHelp=$val"
} else {
    return New-CheckResult -Code "PC-18" -Status "VULN" -Detail "원격 지원이 사용으로 설정됨(기본값 포함)" -Evidence "fAllowToGetHelp=$val"
}

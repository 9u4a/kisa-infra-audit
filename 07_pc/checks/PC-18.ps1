# PC-18 (중) 원격 지원을 금지하도록 정책이 설정
# 판단 기준(가이드 원문): 양호 = 원격 지원이 "사용 안 함"(0) / 취약 = "사용"(1, 기본값)
# W-R10: 그룹 정책 "원격 지원 요청 허용"(HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\fAllowToGetHelp)
# 이 있으면 로컬 설정(Control\Remote Assistance)보다 우선한다 - 예전에는 로컬 값만 봤다.

$gpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$val = Test-RegistryValue -Path $gpoPath -Name "fAllowToGetHelp"
$src = "$gpoPath (그룹 정책)"
if ($null -eq $val) {
    $val = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp"
    $src = "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance"
}

# Windows 클라이언트 기본값은 1(사용/취약)이므로 미설정을 안전하다고 가정하지 않는다.
if ($val -eq 0) {
    return New-CheckResult -Code "PC-18" -Status "GOOD" -Detail "원격 지원이 사용 안 함으로 설정됨" -Evidence "$src!fAllowToGetHelp=$val"
} else {
    return New-CheckResult -Code "PC-18" -Status "VULN" -Detail "원격 지원이 사용으로 설정됨(기본값 포함)" -Evidence "$src!fAllowToGetHelp=$val"
}

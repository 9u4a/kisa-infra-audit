# PC-02 (상) 비밀번호 관리정책 설정
# 판단 기준(가이드 원문): 양호 = 복잡성을 만족하는 비밀번호 정책이 설정된 경우
#                        취약 = 미사용 또는 추측하기 쉬운 짧은 비밀번호 허용
# 자동화 범위: PasswordComplexity=1 및 MinimumPasswordLength>=8 로 판정.

$complexity = Get-SecPolicyValue -Section "System Access" -Name "PasswordComplexity"
$minLen = Get-SecPolicyValue -Section "System Access" -Name "MinimumPasswordLength"

if ($null -eq $complexity) {
    return New-CheckResult -Code "PC-02" -Status "ERROR" -Detail "secedit 에서 비밀번호 정책 값을 조회하지 못함"
}

$evidence = "PasswordComplexity=$complexity MinimumPasswordLength=$minLen"

if ($complexity -eq "1" -and [int]$minLen -ge 8) {
    return New-CheckResult -Code "PC-02" -Status "GOOD" -Detail "비밀번호 복잡성 사용 및 최소 길이 8자 이상으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-02" -Status "VULN" -Detail "비밀번호 복잡성 미사용이거나 최소 길이가 8자 미만임" -Evidence $evidence
}

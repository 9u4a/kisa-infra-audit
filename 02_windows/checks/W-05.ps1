# W-05 (상) 해독 가능한 암호화를 사용하여 암호 저장 해제
# 판단 기준(가이드 원문): 양호 = "해독 가능한 암호화 사용" 정책이 "사용 안 함" / 취약 = "사용"

$val = Get-SecPolicyValue -Section "System Access" -Name "ClearTextPassword"
if ($null -eq $val) {
    return New-CheckResult -Code "W-05" -Status "ERROR" -Detail "secedit 에서 ClearTextPassword 값을 조회하지 못함"
}

if ($val -eq "0") {
    return New-CheckResult -Code "W-05" -Status "GOOD" -Detail "해독 가능한 암호화를 사용하여 암호 저장 정책이 사용 안 함으로 설정됨" -Evidence "ClearTextPassword=$val"
} else {
    return New-CheckResult -Code "W-05" -Status "VULN" -Detail "해독 가능한 암호화를 사용하여 암호 저장 정책이 사용으로 설정됨" -Evidence "ClearTextPassword=$val"
}

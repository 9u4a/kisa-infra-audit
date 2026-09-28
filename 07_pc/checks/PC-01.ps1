# PC-01 (상) 비밀번호의 주기적 변경
# 판단 기준(가이드 원문): 양호 = 최대 암호 사용 기간이 90일 이하 / 취약 = 제한 없음 또는 90일 초과

$val = Get-SecPolicyValue -Section "System Access" -Name "MaximumPasswordAge"
if ($null -eq $val) {
    return New-CheckResult -Code "PC-01" -Status "ERROR" -Detail "secedit 에서 MaximumPasswordAge 값을 조회하지 못함"
}

$days = [int]$val
if ($days -gt 0 -and $days -le 90) {
    return New-CheckResult -Code "PC-01" -Status "GOOD" -Detail "최대 암호 사용 기간이 ${days}일로 설정됨 (90일 이하)" -Evidence "MaximumPasswordAge=$days"
} else {
    return New-CheckResult -Code "PC-01" -Status "VULN" -Detail "최대 암호 사용 기간이 ${days}일로 설정됨 (제한 없음 또는 90일 초과)" -Evidence "MaximumPasswordAge=$days"
}

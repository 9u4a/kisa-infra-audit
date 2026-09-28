# W-04 (상) 계정 잠금 임계값 설정
# 판단 기준(가이드 원문): 양호 = 계정 잠금 임계값이 5 이하 / 취약 = 5 초과 (0=미설정도 취약)

$val = Get-SecPolicyValue -Section "System Access" -Name "LockoutBadCount"
if ($null -eq $val) {
    return New-CheckResult -Code "W-04" -Status "ERROR" -Detail "secedit 에서 LockoutBadCount 값을 조회하지 못함"
}

$n = [int]$val
if ($n -ge 1 -and $n -le 5) {
    return New-CheckResult -Code "W-04" -Status "GOOD" -Detail "계정 잠금 임계값이 ${n}회로 설정됨 (5 이하)" -Evidence "LockoutBadCount=$n"
} else {
    return New-CheckResult -Code "W-04" -Status "VULN" -Detail "계정 잠금 임계값이 ${n}회로 설정됨 (미설정이거나 5 초과)" -Evidence "LockoutBadCount=$n"
}

# W-08 (중) 계정 잠금 기간 설정
# 판단 기준(가이드 원문): 양호 = 계정 잠금 기간 및 다시 설정 기간이 60분 이상
#                        취약 = 미설정 또는 60분 미만

$duration = Get-SecPolicyValue -Section "System Access" -Name "LockoutDuration"
$reset = Get-SecPolicyValue -Section "System Access" -Name "ResetLockoutCount"

if ($null -eq $duration -or $null -eq $reset) {
    return New-CheckResult -Code "W-08" -Status "ERROR" -Detail "secedit 에서 LockoutDuration/ResetLockoutCount 값을 조회하지 못함"
}

$d = [int]$duration; $r = [int]$reset
$evidence = "LockoutDuration=$d(분) ResetLockoutCount=$r(분)"

if ($d -ge 60 -and $r -ge 60) {
    return New-CheckResult -Code "W-08" -Status "GOOD" -Detail "계정 잠금 기간(${d}분) 및 다시 설정 기간(${r}분)이 모두 60분 이상임" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-08" -Status "VULN" -Detail "계정 잠금 기간 또는 다시 설정 기간이 60분 미만이거나 미설정임" -Evidence $evidence
}

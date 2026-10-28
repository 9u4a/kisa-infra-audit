# W-08 (중) 계정 잠금 기간 설정
# 판단 기준(가이드 원문): 양호 = 계정 잠금 기간 및 다시 설정 기간이 60분 이상
#                        취약 = 미설정 또는 60분 미만
# W-R8: 잠금 임계값(LockoutBadCount)이 0 이면 계정 잠금 자체가 꺼져 있고 secedit 이 기간 값을 내보내지 않는다 -
# 예전에는 이를 ERROR 로 냈다(가이드상 "미설정" = 취약). LockoutDuration=-1 은 "관리자가 해제할 때까지 잠금"
# (Microsoft 문서: Account lockout duration -1)이라 60분 이상과 같게 본다(예전에는 -1 < 60 으로 VULN).

$bad = Get-SecPolicyValue -Section "System Access" -Name "LockoutBadCount"
$duration = Get-SecPolicyValue -Section "System Access" -Name "LockoutDuration"
$reset = Get-SecPolicyValue -Section "System Access" -Name "ResetLockoutCount"

if ($null -ne $bad -and [int]$bad -eq 0) {
    return New-CheckResult -Code "W-08" -Status "VULN" -Detail "계정 잠금 임계값이 0(잠금 사용 안 함)이라 계정 잠금 기간이 설정되어 있지 않음" -Evidence "LockoutBadCount=$bad LockoutDuration=$duration ResetLockoutCount=$reset"
}
if ($null -eq $duration -or $null -eq $reset) {
    return New-CheckResult -Code "W-08" -Status "ERROR" -Detail "secedit 에서 LockoutDuration/ResetLockoutCount 값을 조회하지 못함"
}

$d = [int]$duration; $r = [int]$reset
$evidence = "LockoutBadCount=$bad LockoutDuration=$d(분, -1=관리자 해제 시까지) ResetLockoutCount=$r(분)"
$durationOk = ($d -eq -1 -or $d -ge 60)

if ($durationOk -and $r -ge 60) {
    return New-CheckResult -Code "W-08" -Status "GOOD" -Detail "계정 잠금 기간($(if ($d -eq -1) { '관리자 해제 시까지' } else { "${d}분" })) 및 다시 설정 기간(${r}분)이 모두 60분 이상임" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-08" -Status "VULN" -Detail "계정 잠금 기간 또는 다시 설정 기간이 60분 미만이거나 미설정임" -Evidence $evidence
}

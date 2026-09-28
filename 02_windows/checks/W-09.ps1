# W-09 (상) 비밀번호 관리 정책 설정
# 판단 기준(가이드 원문): 양호 = 비밀번호 복잡성, 최소 길이(8자), 최대(90일 이하)/최소(1일 이상)
#                        사용 기간, 기억 개수(4개 이상) 정책이 모두 적용된 경우

$complexity = Get-SecPolicyValue -Section "System Access" -Name "PasswordComplexity"
$minLen = Get-SecPolicyValue -Section "System Access" -Name "MinimumPasswordLength"
$maxAge = Get-SecPolicyValue -Section "System Access" -Name "MaximumPasswordAge"
$minAge = Get-SecPolicyValue -Section "System Access" -Name "MinimumPasswordAge"
$history = Get-SecPolicyValue -Section "System Access" -Name "PasswordHistorySize"

if ($null -eq $complexity) {
    return New-CheckResult -Code "W-09" -Status "ERROR" -Detail "secedit 에서 비밀번호 정책 값을 조회하지 못함"
}

$evidence = "PasswordComplexity=$complexity MinimumPasswordLength=$minLen MaximumPasswordAge=$maxAge MinimumPasswordAge=$minAge PasswordHistorySize=$history"

$violations = @()
if ($complexity -ne "1") { $violations += "복잡성 미사용" }
if ([int]$minLen -lt 8) { $violations += "최소 길이 8자 미만" }
if ([int]$maxAge -le 0 -or [int]$maxAge -gt 90) { $violations += "최대 사용 기간 미설정 또는 90일 초과" }
if ([int]$minAge -lt 1) { $violations += "최소 사용 기간 1일 미만" }
if ([int]$history -lt 4) { $violations += "암호 기억 개수 4개 미만" }

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-09" -Status "GOOD" -Detail "비밀번호 관리 정책(복잡성/길이/기간/기록)이 모두 기준을 충족함" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-09" -Status "VULN" -Detail ("비밀번호 관리 정책 미충족: " + ($violations -join ", ")) -Evidence $evidence
}

# W-54 (중) Dos 공격 방어 레지스트리 설정
# 판단 기준(가이드 원문): 양호 = 4개 레지스트리 값이 모두 기준대로 설정된 경우
#   SynAttackProtect>=1, EnableDeadGWDetect=0, KeepAliveTime=300000, NoNameReleaseOnDemand=1
#                        취약 = 설정되어 있지 않은 경우

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$syn = Test-RegistryValue -Path $path -Name "SynAttackProtect"
$deadGw = Test-RegistryValue -Path $path -Name "EnableDeadGWDetect"
$keepAlive = Test-RegistryValue -Path $path -Name "KeepAliveTime"
$noNameRelease = Test-RegistryValue -Path $path -Name "NoNameReleaseOnDemand"

$evidence = "SynAttackProtect=$syn EnableDeadGWDetect=$deadGw KeepAliveTime=$keepAlive NoNameReleaseOnDemand=$noNameRelease"

$violations = @()
if (-not $syn -or [int]$syn -lt 1) { $violations += "SynAttackProtect" }
if ($null -eq $deadGw -or [int]$deadGw -ne 0) { $violations += "EnableDeadGWDetect" }
if ($null -eq $keepAlive -or [int]$keepAlive -ne 300000) { $violations += "KeepAliveTime" }
if ($null -eq $noNameRelease -or [int]$noNameRelease -ne 1) { $violations += "NoNameReleaseOnDemand" }

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-54" -Status "GOOD" -Detail "DoS 공격 방어 레지스트리 4개 항목이 모두 기준대로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-54" -Status "VULN" -Detail ("DoS 방어 레지스트리 기준 미충족: " + ($violations -join ", ")) -Evidence $evidence
}

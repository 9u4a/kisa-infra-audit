# W-56 (중) SMB 세션 중단 관리 설정
# 판단 기준(가이드 원문): 양호 = "로그온 시간 만료 시 연결 끊기"=사용 및 유휴 시간 15분 이하
#                        취약 = 사용 안 함 또는 15분 초과

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
$forceLogoff = Test-RegistryValue -Path $path -Name "enableforcedlogoff"
$idle = Test-RegistryValue -Path $path -Name "autodisconnect"

$evidence = "enableforcedlogoff=$forceLogoff autodisconnect=$idle(분)"

if ($forceLogoff -eq 1 -and $null -ne $idle -and [int]$idle -le 15) {
    return New-CheckResult -Code "W-56" -Status "GOOD" -Detail "로그온 시간 만료 시 연결 끊기가 사용 중이며 유휴 시간이 ${idle}분(15분 이하)으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-56" -Status "VULN" -Detail "로그온 시간 만료 시 연결 끊기가 비활성화되어 있거나 유휴 시간이 15분을 초과함" -Evidence $evidence
}

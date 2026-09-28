# W-36 (중) 원격터미널 접속 타임아웃 설정
# 판단 기준(가이드 원문): 양호 = RDP 미사용 또는 유휴 세션 제한 시간이 30분 이하로 설정된 경우
#                        취약 = 미설정 또는 30분 초과

$deny = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
if ($deny -eq 1) {
    return New-CheckResult -Code "W-36" -Status "GOOD" -Detail "원격 데스크톱 서비스가 비활성화되어 있음" -Evidence "fDenyTSConnections=$deny"
}

$gpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$idleMs = Test-RegistryValue -Path $gpoPath -Name "MaxIdleTime"
if ($null -eq $idleMs) {
    $idleMs = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "MaxIdleTime"
}

if ($null -eq $idleMs -or [int]$idleMs -eq 0) {
    return New-CheckResult -Code "W-36" -Status "VULN" -Detail "원격터미널 유휴 세션 제한 시간이 설정되어 있지 않음(무제한)" -Evidence "MaxIdleTime=$idleMs"
}

$minutes = [int]$idleMs / 60000
if ($minutes -le 30) {
    return New-CheckResult -Code "W-36" -Status "GOOD" -Detail "원격터미널 유휴 세션 제한 시간이 ${minutes}분으로 설정됨 (30분 이하)" -Evidence "MaxIdleTime=$idleMs ms"
} else {
    return New-CheckResult -Code "W-36" -Status "VULN" -Detail "원격터미널 유휴 세션 제한 시간이 ${minutes}분으로 30분을 초과함" -Evidence "MaxIdleTime=$idleMs ms"
}

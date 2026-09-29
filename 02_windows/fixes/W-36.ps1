# W-36 (중) 원격터미널 접속 타임아웃 설정 [fix: auto]
# checks/W-36.ps1: 양호 = MaxIdleTime <= 30분. 가이드 권고 상한값(30분=1800000ms)으로 설정한다.

$deny = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
if ($deny -eq 1) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "원격 데스크톱 서비스가 비활성화되어 있어 해당 없음"; $Global:FixEvidence = ""
    return
}

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "MaxIdleTime" -Value 1800000 -Type DWord

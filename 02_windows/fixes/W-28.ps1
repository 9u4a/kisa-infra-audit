# W-28 (중) 터미널 서비스 암호화 수준 설정 [fix: confirm]
# checks/W-28.ps1: 양호 = MinEncryptionLevel >= 2. 가이드 권고값(3=높음)으로 설정한다.

$deny = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
if ($deny -eq 1) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "원격 데스크톱 서비스가 비활성화되어 있어 해당 없음"; $Global:FixEvidence = ""
    return
}

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "MinEncryptionLevel" -Value 3 -Type DWord

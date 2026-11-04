# W-56 (중) SMB 세션 중단 관리 설정 [fix: auto]
# 변경: HKLM\...\Services\LanmanServer\Parameters enableforcedlogoff = 1, autodisconnect = 15 (DWORD, 유휴 15분)

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
Set-FixRegistryValue -Path $path -Name "enableforcedlogoff" -Value 1 -Type DWord
$d1 = $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "autodisconnect" -Value 15 -Type DWord
$Global:FixDetail = "$d1; $($Global:FixDetail)"

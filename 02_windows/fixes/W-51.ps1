# W-51 (상) SAM 계정과 공유의 익명 열거 허용 안 함 [fix: confirm]
# 변경: HKLM\SYSTEM\CurrentControlSet\Control\Lsa RestrictAnonymous = 1, RestrictAnonymousSAM = 1 (DWORD)

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1 -Type DWord
$d1 = $Global:FixDetail
Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1 -Type DWord
$Global:FixDetail = "$d1; $($Global:FixDetail)"

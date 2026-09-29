# W-13 (중) 콘솔 로그온 시 로컬 계정에서 빈 암호 사용 제한 [fix: auto]
# checks/W-13.ps1: 양호 = LimitBlankPasswordUse=1(또는 미설정=기본값)

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LimitBlankPasswordUse" -Value 1 -Type DWord

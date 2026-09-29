# W-07 (중) Everyone 사용 권한을 익명 사용자에 적용 [fix: confirm]
# checks/W-07.ps1: 양호 = EveryoneIncludesAnonymous=0(또는 미설정)

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "EveryoneIncludesAnonymous" -Value 0 -Type DWord

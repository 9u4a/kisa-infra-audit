# W-10 (중) 마지막 사용자 이름 표시 안 함 [fix: auto]
# checks/W-10.ps1: 양호 = DontDisplayLastUserName=1

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DontDisplayLastUserName" -Value 1 -Type DWord

# W-15 (상) 사용자 개인키 사용 시 암호 입력 [fix: auto]
# checks/W-15.ps1: 양호 = ForceKeyProtection=2(사용할 때마다 암호 입력)

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect" -Name "ForceKeyProtection" -Value 2 -Type DWord

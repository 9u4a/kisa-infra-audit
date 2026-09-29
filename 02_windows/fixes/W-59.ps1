# W-59 (중) LAN Manager 인증 수준 [fix: auto]

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 3 -Type DWord

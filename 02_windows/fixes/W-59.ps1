# W-59 (중) LAN Manager 인증 수준 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 3 -Type DWord

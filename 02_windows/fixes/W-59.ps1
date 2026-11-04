# W-59 (중) LAN Manager 인증 수준 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 변경: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LmCompatibilityLevel = 3 (DWORD, NTLMv2 응답만 보냄)

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 3 -Type DWord

# PC-03 (중) 복구 콘솔에서 자동 로그온을 금지하도록 설정 [fix: auto]
# 변경: HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SecurityLevel = 0 (DWORD)

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole" -Name "SecurityLevel" -Value 0 -Type DWord

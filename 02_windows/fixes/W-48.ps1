# W-48 (상) 로그온하지 않고 시스템 종료 허용 [fix: auto]
# 변경: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\ShutdownWithoutLogon = 0 (DWORD)

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ShutdownWithoutLogon" -Value 0 -Type DWord

# W-48 (상) 로그온하지 않고 시스템 종료 허용 [fix: auto]

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ShutdownWithoutLogon" -Value 0 -Type DWord

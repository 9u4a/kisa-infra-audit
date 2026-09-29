# W-53 (상) 이동식 미디어 포맷 및 꺼내기 허용 [fix: auto]

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AllocateDASD" -Value "0" -Type String

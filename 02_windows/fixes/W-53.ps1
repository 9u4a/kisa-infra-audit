# W-53 (상) 이동식 미디어 포맷 및 꺼내기 허용 [fix: auto]
# 변경: HKLM\...\Windows NT\CurrentVersion\Winlogon\AllocateDASD = "0" (문자열, Administrators 만 허용)

Set-FixRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AllocateDASD" -Value "0" -Type String

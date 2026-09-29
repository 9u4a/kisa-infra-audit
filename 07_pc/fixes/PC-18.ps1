# PC-18 (중) 원격 지원을 금지하도록 정책이 설정 [fix: confirm]

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -Type DWord

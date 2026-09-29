# W-55 (중) 사용자가 프린터 드라이버를 설치할 수 없게 함 [fix: auto]

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers" -Name "AddPrinterDrivers" -Value 1 -Type DWord

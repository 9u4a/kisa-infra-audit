# W-54 (중) Dos 공격 방어 레지스트리 설정 [fix: confirm]
# checks/W-54.ps1 기준값 4개를 그대로 설정한다.

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$details = @()

Set-FixRegistryValue -Path $path -Name "SynAttackProtect" -Value 1 -Type DWord
$details += $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "EnableDeadGWDetect" -Value 0 -Type DWord
$details += $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "KeepAliveTime" -Value 300000 -Type DWord
$details += $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "NoNameReleaseOnDemand" -Value 1 -Type DWord
$details += $Global:FixDetail

$Global:FixDetail = $details -join "; "

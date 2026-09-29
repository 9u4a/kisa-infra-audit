# W-60 (중) 보안 채널 데이터 디지털 암호화 또는 서명 [fix: confirm]
# checks/W-60.ps1 과 동일하게 도메인 가입 여부를 먼저 확인한다(워크그룹은 NA).

try {
    $partOfDomain = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
} catch {
    $partOfDomain = $false
}

if (-not $partOfDomain) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "워크그룹 환경으로 해당 정책이 적용되지 않음"; $Global:FixEvidence = ""
    return
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
$details = @()
Set-FixRegistryValue -Path $path -Name "RequireSignOrSeal" -Value 1 -Type DWord
$details += $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "SealSecureChannel" -Value 1 -Type DWord
$details += $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "SignSecureChannel" -Value 1 -Type DWord
$details += $Global:FixDetail
$Global:FixDetail = $details -join "; "

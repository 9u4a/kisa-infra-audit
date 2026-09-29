# PC-12 (중) Windows 자동 로그인 점검 [fix: auto]
# 02_windows/fixes/W-52.ps1 과 동일한 대상/조치 (PC 카테고리는 secedit 확인 없이 레지스트리만 다룸)

$path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$val = Test-RegistryValue -Path $path -Name "AutoAdminLogon"

if ($null -eq $val) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "AutoAdminLogon 값이 이미 설정되어 있지 않음"; $Global:FixEvidence = ""
    return
}

Set-FixRegistryValue -Path $path -Name "AutoAdminLogon" -Value "0" -Type String

if (Test-RegistryValue -Path $path -Name "DefaultPassword") {
    Remove-FixRegistryValue -Path $path -Name "DefaultPassword"
    $Global:FixDetail = "AutoAdminLogon=0 로 설정하고 평문 저장된 DefaultPassword 값을 제거함"
}

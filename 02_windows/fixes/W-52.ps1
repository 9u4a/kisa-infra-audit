# W-52 (상) Autologon 기능 제어 [fix: confirm]
# checks/W-52.ps1: 양호 = AutoAdminLogon 값이 없거나 0. 값이 존재하는 경우에만 0으로 설정한다.

$path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$val = Test-RegistryValue -Path $path -Name "AutoAdminLogon"

if ($null -eq $val) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "AutoAdminLogon 값이 이미 설정되어 있지 않음"; $Global:FixEvidence = ""
    return
}

Set-FixRegistryValue -Path $path -Name "AutoAdminLogon" -Value "0" -Type String

# 자동 로그인 비밀번호가 평문으로 저장되어 있었다면 함께 제거한다(가이드 조치 방법의 일부).
if (Test-RegistryValue -Path $path -Name "DefaultPassword") {
    Remove-FixRegistryValue -Path $path -Name "DefaultPassword"
    $Global:FixDetail = "AutoAdminLogon=0 로 설정하고 평문 저장된 DefaultPassword 값을 제거함"
}

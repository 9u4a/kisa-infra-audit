# W-41 (중) NTP 및 시각 동기화 설정
# 판단 기준(가이드 원문): 양호 = NTP 및 시각 동기화를 설정한 경우 / 취약 = 설정하지 않은 경우

$svc = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-41" -Status "VULN" -Detail "Windows Time(W32Time) 서비스가 중지되어 있어 시각 동기화가 이루어지지 않음" -Evidence "W32Time Status=$($svc.Status)"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
$type = Test-RegistryValue -Path $path -Name "Type"
$ntpServer = Test-RegistryValue -Path $path -Name "NtpServer"

$evidence = "Type=$type NtpServer=$ntpServer"

if ($type -eq "NoSync") {
    return New-CheckResult -Code "W-41" -Status "VULN" -Detail "시각 동기화 유형이 NoSync(동기화 안 함)로 설정되어 있음" -Evidence $evidence
} elseif ($ntpServer) {
    return New-CheckResult -Code "W-41" -Status "GOOD" -Detail "NTP 서버와의 시각 동기화가 설정되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-41" -Status "VULN" -Detail "NTP 서버가 설정되어 있지 않음" -Evidence $evidence
}

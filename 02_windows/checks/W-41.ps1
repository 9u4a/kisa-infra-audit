# W-41 (중) NTP 및 시각 동기화 설정
# 판단 기준(가이드 원문): 양호 = NTP 및 시각 동기화를 설정한 경우 / 취약 = 설정하지 않은 경우

# 서비스 조회 실패(비관리자 배치 실행 등)를 "중지 = VULN" 으로 읽지 않는다(CI 실측: 비관리자 실행에서만 VULN)
try { $svc = Get-ServiceChecked -Name "W32Time" }
catch { return New-CheckResult -Code "W-41" -Status "ERROR" -Detail "Windows Time(W32Time) 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
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

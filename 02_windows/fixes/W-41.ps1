# W-41 (중) NTP 및 시각 동기화 설정 [fix: auto]
# checks/W-41.ps1: 양호 = W32Time 구동 중 + NtpServer 설정. 조직별 내부 NTP 서버 주소는
# 스크립트가 알 수 없으므로, Windows 기본 내장 시간 서버(time.windows.com)를 사용한다 -
# 조직 정책상 다른 서버를 써야 하면 이 값은 언제든 재설정 가능한 일반 값이라 U-28 류의
# "안전한 값을 알 수 없는" 문제에 해당하지 않는다.

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -Value "NTP" -Type String
Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "NtpServer" -Value "time.windows.com,0x1" -Type String

$svc = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne "Running") {
    try {
        Set-Service -Name "W32Time" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "W32Time" -ErrorAction Stop
        $Global:FixDetail = "$($Global:FixDetail); W32Time 서비스를 시작함"
    } catch {
        $Global:FixDetail = "$($Global:FixDetail); W32Time 서비스 시작 실패: $($_.Exception.Message)"
    }
}

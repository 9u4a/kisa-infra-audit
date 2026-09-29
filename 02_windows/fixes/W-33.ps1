# W-33 (하) HTTP/FTP/SMTP 배너 차단 [fix: auto]
# checks/W-33.ps1: VULN 은 HTTP Server 헤더 노출인 경우에만 발생(FTP/SMTP 는 MANUAL). IIS 10+
# 의 removeServerHeader 로 Server 헤더 자체를 제거한다(03_web/checks/iis/WEB-16.ps1 과 동일 설정).

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "WebAdministration 모듈이 없어 Server 헤더 제거 설정을 변경할 수 없음"
    $Global:FixEvidence = ""
    return
}
Import-Module WebAdministration -ErrorAction SilentlyContinue

Set-FixWebConfigProperty -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST"

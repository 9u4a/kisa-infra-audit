# W-33 (하) HTTP/FTP/SMTP 배너 차단 [fix: auto]
# checks/W-33.ps1: VULN 은 HTTP Server 헤더 노출인 경우에만 발생(FTP/SMTP 는 MANUAL). IIS 10+
# 의 removeServerHeader 로 Server 헤더 자체를 제거한다(03_web WEB-16 과 같은 설정·같은 공용 함수).
# 진단은 실제 응답 헤더를 보므로 서버 전역만 바꾸면 사이트 재정의(web.config/location 의 removeServerHeader=false)가
# 남아 재검증 실패 → 원복으로 끝났다(CI 실측) - 공용 함수가 전역 + 사이트별 재정의를 함께 고친다.

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "WebAdministration 모듈이 없어 Server 헤더 제거 설정을 변경할 수 없음"
    $Global:FixEvidence = ""
    return
}

Invoke-FixIisRemoveServerHeader

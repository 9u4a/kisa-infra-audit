# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = HTTP 응답 헤더에서 서버 정보가 노출되지 않는 경우
#                        취약 = 노출되는 경우
# 자동화 범위: IIS 10(1709+)의 requestFiltering@removeServerHeader 설정(Server 헤더 자체 제거)
# 을 확인한다. 기본값은 false(=Server 헤더 노출)이므로 명시적으로 true 로 설정된 경우만 양호로
# 본다. 구버전 IIS(설정 자체가 없는 경우)는 URL Rewrite 규칙 등 다른 수단이 필요해 MANUAL.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-16" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

$removeHeader = Get-IisConfigValue -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader"
if ($null -eq $removeHeader) {
    return New-CheckResult -Code "WEB-16" -Status "MANUAL" -Detail "removeServerHeader 속성을 지원하지 않는 IIS 버전(10.0 1709 미만)으로 추정 - URL Rewrite 등 대체 수단 적용 여부를 수동 확인 필요"
}
if ($removeHeader -eq $true) {
    return New-CheckResult -Code "WEB-16" -Status "GOOD" -Detail "Server 응답 헤더가 제거되도록 설정됨(removeServerHeader = true)" -Evidence "removeServerHeader = $removeHeader"
}
return New-CheckResult -Code "WEB-16" -Status "VULN" -Detail "Server 응답 헤더가 노출됨(removeServerHeader = false, 기본값)" -Evidence "removeServerHeader = $removeHeader"

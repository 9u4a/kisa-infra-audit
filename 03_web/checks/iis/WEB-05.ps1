# WEB-05 (상) 지정하지 않은 CGI/ISAPI 실행 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = CGI 미사용 또는 실행 가능 디렉터리를 제한한 경우
#                        취약 = CGI 사용 중이며 실행 가능 디렉터리를 제한하지 않은 경우
# 자동화 범위: 서버 전역 system.webServer/security/isapiCgiRestriction 의
# notListedCgisAllowed/notListedIsapisAllowed 가 false 이면(명시 목록만 허용) 양호로 본다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-05" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

$cgiAllowed = Get-IisConfigValue -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedCgisAllowed"
$isapiAllowed = Get-IisConfigValue -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedIsapisAllowed"
$evid = "notListedCgisAllowed = $cgiAllowed`nnotListedIsapisAllowed = $isapiAllowed"

if ($null -eq $cgiAllowed -and $null -eq $isapiAllowed) {
    return New-CheckResult -Code "WEB-05" -Status "MANUAL" -Detail "isapiCgiRestriction 설정을 조회할 수 없음 - 수동 확인 필요" -Evidence $evid
}

if ($cgiAllowed -eq $true -or $isapiAllowed -eq $true) {
    return New-CheckResult -Code "WEB-05" -Status "VULN" -Detail "명시적으로 등록되지 않은 CGI/ISAPI 실행이 허용되어 있음(notListedCgisAllowed/notListedIsapisAllowed = true)" -Evidence $evid
}
return New-CheckResult -Code "WEB-05" -Status "GOOD" -Detail "명시적으로 등록된 CGI/ISAPI 목록만 실행이 허용됨" -Evidence $evid

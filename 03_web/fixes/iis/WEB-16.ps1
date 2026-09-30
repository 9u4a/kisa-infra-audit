# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한 [IIS] — 조치 [fix: auto]

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}

$removeHeader = Get-IisConfigValue -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader"
if ($null -eq $removeHeader) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "removeServerHeader 속성을 지원하지 않는 IIS 버전으로 추정됨 - URL Rewrite 등 대체 수단을 수동으로 구성할 것"
    $Global:FixEvidence = ""
    return
}
if ($removeHeader -eq $true) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "이미 Server 헤더가 제거되도록 설정되어 있음"; $Global:FixEvidence = ""
    return
}

Set-FixWebConfigProperty -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST"

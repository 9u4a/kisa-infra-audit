# WEB-05 (상) 지정하지 않은 CGI/ISAPI 실행 제한 [IIS] — 조치 [fix: confirm]
# 서버 전역 설정이라 다른 사이트의 CGI/ISAPI 동작에도 영향을 줄 수 있어 confirm 등급이다.

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}

$cgiAllowed = Get-IisConfigValue -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedCgisAllowed"
$isapiAllowed = Get-IisConfigValue -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedIsapisAllowed"

if ($null -eq $cgiAllowed -and $null -eq $isapiAllowed) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "isapiCgiRestriction 설정을 조회할 수 없음"; $Global:FixEvidence = ""
    return
}

$details = @()
if ($cgiAllowed -eq $true) {
    Set-FixWebConfigProperty -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedCgisAllowed" -Value $false -PSPath "MACHINE/WEBROOT/APPHOST"
    $details += $Global:FixDetail
}
if ($isapiAllowed -eq $true) {
    Set-FixWebConfigProperty -Filter "system.webServer/security/isapiCgiRestriction" -Name "notListedIsapisAllowed" -Value $false -PSPath "MACHINE/WEBROOT/APPHOST"
    $details += $Global:FixDetail
}

if ($details.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "명시 목록 외 CGI/ISAPI 실행을 차단함: " + ($details -join "; ")
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "이미 명시 목록만 허용되어 있음"
}
$Global:FixEvidence = ""

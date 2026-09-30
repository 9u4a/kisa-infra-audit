# WEB-22 (하) 에러 페이지 관리 [IIS] — 조치 [fix: auto]
# errorMode=Detailed(원격에도 상세 오류 노출)인 사이트를 DetailedLocalOnly(로컬에서만 상세,
# IIS 기본값)로 되돌린다 - 원격에는 일반 오류만 노출되면서도 로컬 디버깅은 유지되는 안전한 값.

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($site in $sites) {
    $mode = Get-IisConfigValue -Filter "system.webServer/httpErrors" -Name "errorMode" -SiteName $site
    if ("$mode" -eq "Detailed") {
        Set-FixWebConfigProperty -Filter "system.webServer/httpErrors" -Name "errorMode" -Value "DetailedLocalOnly" -PSPath "IIS:\Sites\$site"
        if ($Global:FixStatus -eq "APPLIED") { $applied += $site }
    }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "errorMode 을 DetailedLocalOnly 로 되돌린 사이트: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "errorMode=Detailed 인 사이트가 없음(이미 정상)"
}
$Global:FixEvidence = ""

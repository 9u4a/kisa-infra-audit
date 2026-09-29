# WEB-22 (하) 에러 페이지 관리 [IIS]
# 판단 기준(가이드 원문): 양호 = 에러 페이지가 별도로 지정된 경우
#                        취약 = 지정되지 않거나 에러 발생 시 중요 정보가 노출되는 경우
# 자동화 범위: system.webServer/httpErrors@errorMode 를 사이트별로 확인한다. "Detailed" 는
# 원격 클라이언트에게도 상세 오류(스택 트레이스 등)를 그대로 노출하므로 취약, "Custom" 또는
# "DetailedLocalOnly"(로컬에서만 상세, 기본값)는 양호로 본다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-22" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-22" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $mode = Get-IisConfigValue -Filter "system.webServer/httpErrors" -Name "errorMode" -SiteName $site
    $evid += "[$site] httpErrors.errorMode = $mode"
    if ("$mode" -eq "Detailed") { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-22" -Status "VULN" -Detail "원격에도 상세 오류를 노출하는(errorMode=Detailed) 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-22" -Status "GOOD" -Detail "모든 사이트가 사용자 지정/로컬전용 오류 페이지로 설정됨" -Evidence ($evid -join "`n")

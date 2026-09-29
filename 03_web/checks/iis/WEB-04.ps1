# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 디렉터리 리스팅 미설정 / 취약 = 설정됨
# 자동화 범위: system.webServer/directoryBrowse@enabled 를 사이트별로 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-04" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-04" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $enabled = Get-IisConfigValue -Filter "system.webServer/directoryBrowse" -Name "enabled" -SiteName $site
    $evid += "[$site] directoryBrowse.enabled = $enabled"
    if ($enabled -eq $true) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-04" -Status "VULN" -Detail "디렉터리 리스팅이 활성화된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-04" -Status "GOOD" -Detail "모든 사이트에서 디렉터리 리스팅이 비활성화됨" -Evidence ($evid -join "`n")

# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 상위 디렉터리 접근 기능 제거 / 취약 = 제거하지 않은 경우
# 자동화 범위: 가이드는 IIS 6.0(ASP metabase AspEnableParentPaths)과 IIS 7.0+
# (system.webServer/asp@enableParentPaths) 두 경로를 모두 안내한다. 이 도구는 IIS 7.0+ 만
# 대상으로 하므로(2012 R2 이상, 루트 CLAUDE.md 환경 우선순위) web.config/applicationHost.config
# 기준 설정만 확인한다. 기본값은 false(비활성=양호)다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-06" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-06" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $enabled = Get-IisConfigValue -Filter "system.webServer/asp" -Name "enableParentPaths" -SiteName $site
    $evid += "[$site] asp.enableParentPaths = $enabled"
    if ($enabled -eq $true) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-06" -Status "VULN" -Detail "상위 디렉터리 접근(enableParentPaths)이 활성화된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-06" -Status "GOOD" -Detail "모든 사이트에서 상위 디렉터리 접근이 비활성화됨(기본값)" -Evidence ($evid -join "`n")

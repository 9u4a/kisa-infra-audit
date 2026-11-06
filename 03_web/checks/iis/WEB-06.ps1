# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 상위 디렉터리 접근 기능 제거 / 취약 = 제거하지 않은 경우
# 자동화 범위: 가이드는 IIS 6.0(ASP metabase AspEnableParentPaths)과 IIS 7.0+
# (system.webServer/asp@enableParentPaths) 두 경로를 모두 안내한다. 이 도구는 IIS 7.0+ 만
# 대상으로 하므로(2012 R2 이상) web.config/applicationHost.config
# 기준 설정만 확인한다. 기본값은 false(비활성=양호)다.
# 1.5.0 A24: 하위 application·virtual directory 가 자기 web.config 로 다시 켤 수 있어(예전에는 사이트 루트만 봄)
# Get-IisSiteConfigPaths 로 열거한 경로마다 유효 값을 확인한다(WEB-04/18/22 와 같은 방식, 일반 하위 폴더 web.config 는 한계).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-06" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-06" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    foreach ($cp in (Get-IisSiteConfigPaths -SiteName $site)) {
        $enabled = Get-IisConfigValue -Filter "system.webServer/asp" -Name "enableParentPaths" -PSPath $cp.PSPath
        $evid += "[$($cp.Label)] asp.enableParentPaths = $enabled"
        if ($enabled -eq $true) { $vuln += $cp.Label }
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-06" -Status "VULN" -Detail "상위 디렉터리 접근(enableParentPaths)이 활성화된 사이트/경로: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-06" -Status "GOOD" -Detail "모든 사이트(하위 application/virtual directory 포함)에서 상위 디렉터리 접근이 비활성화됨(기본값)" -Evidence ($evid -join "`n")

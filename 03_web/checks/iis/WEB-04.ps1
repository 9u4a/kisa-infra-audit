# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 디렉터리 리스팅 미설정 / 취약 = 설정됨
# 자동화 범위: system.webServer/directoryBrowse@enabled 를 사이트별로 확인한다.
# WEB-R8: 하위 application·virtual directory 가 자기 web.config 로 리스팅을 켤 수 있어(예전에는 사이트 루트만 봄)
# Get-IisSiteConfigPaths 로 열거한 경로마다 유효 값을 확인한다. 일반 하위 폴더의 web.config 는 열거하지 않는다(한계).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-04" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-04" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    foreach ($cp in (Get-IisSiteConfigPaths -SiteName $site)) {
        $enabled = Get-IisConfigValue -Filter "system.webServer/directoryBrowse" -Name "enabled" -PSPath $cp.PSPath
        $evid += "[$($cp.Label)] directoryBrowse.enabled = $enabled"
        if ($enabled -eq $true) { $vuln += $cp.Label }
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-04" -Status "VULN" -Detail "디렉터리 리스팅이 활성화된 사이트/경로: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-04" -Status "GOOD" -Detail "모든 사이트(하위 application/virtual directory 포함)에서 디렉터리 리스팅이 비활성화됨" -Evidence ($evid -join "`n")

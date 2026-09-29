# WEB-13 (상) 웹 서비스 설정 파일 노출 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = DB 연결 파일 접근 제한 및 불필요 스크립트 매핑 제거
#                        취약 = 그렇지 않은 경우
# 자동화 범위: IIS는 기본적으로 requestFiltering 의 hiddenSegments(web.config, bin, App_Data 등)
# 와 fileExtensions 로 설정/구성 파일 직접 다운로드를 차단한다. hiddenSegments 에서 "web.config"
# 항목이 제거(명시적 <remove>)되었는지 확인해 노출 여부를 판정한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-13" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-13" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    try {
        $hidden = Get-WebConfiguration -Filter "system.webServer/security/requestFiltering/hiddenSegments/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop
        $names = @($hidden | ForEach-Object { $_.segment })
    } catch {
        $names = @()
    }
    $hasWebConfig = $names -contains "web.config"
    $evid += "[$site] hiddenSegments = $($names -join ', ')"
    if (-not $hasWebConfig) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-13" -Status "VULN" -Detail "web.config 등 설정 파일이 hiddenSegments 로 보호되지 않는 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-13" -Status "GOOD" -Detail "모든 사이트에서 설정 파일(web.config)이 hiddenSegments 로 보호됨(기본값)" -Evidence ($evid -join "`n")

# WEB-15 (상) 웹 서비스의 불필요한 스크립트 매핑 제거 [IIS]
# 판단 기준(가이드 원문): 양호 = 불필요한 스크립트 매핑이 없는 경우 / 취약 = 있는 경우
# 자동화 범위: IIS 6.0 시절의 대표적 취약 확장자(.htr/.idc/.stm/.shtm/.shtml/.printer/.htw/
# .ida/.idq)가 handler mapping 에 남아 있는지 사이트별로 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-15" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-15" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$dangerExt = @(".htr", ".idc", ".stm", ".shtm", ".shtml", ".printer", ".htw", ".ida", ".idq")

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    try {
        $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop
    } catch {
        $handlers = @()
    }
    $hit = @()
    foreach ($h in $handlers) {
        foreach ($ext in $dangerExt) {
            if ($h.path -ilike "*$ext") { $hit += "$($h.name)($($h.path))" }
        }
    }
    $evid += "[$site] 위험 확장자 매핑: $(if ($hit.Count -gt 0) { $hit -join ', ' } else { '없음' })"
    if ($hit.Count -gt 0) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-15" -Status "VULN" -Detail "불필요한(취약) 스크립트 매핑이 남아있는 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-15" -Status "GOOD" -Detail "대표 취약 확장자 스크립트 매핑이 존재하지 않음" -Evidence ($evid -join "`n")

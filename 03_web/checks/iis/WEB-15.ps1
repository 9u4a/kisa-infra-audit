# WEB-15 (상) 웹 서비스의 불필요한 스크립트 매핑 제거 [IIS]
# 판단 기준(가이드 원문): 양호 = 불필요한 스크립트 매핑이 없는 경우 / 취약 = 있는 경우
# guide.json automation=manual: 어떤 매핑이 "불필요한지"는 운영 중인 애플리케이션에 달려 있어 자동으로 양호를 줄 수 없다.
# 1.5.0: 예전에는 IIS 6.0 시절 대표 취약 확장자(.htr/.idc/.stm/.shtm/.shtml/.printer/.htw/.ida/.idq) 목록에 없으면 GOOD 이었다
# (가이드 기준과 다른 판정, deviation 미기록). 이제
#   - 대표 취약 확장자 매핑이 남아 있으면 VULN(불필요 매핑이 존재함이 분명한 경우 - guide.json deviation 기록)
#   - 없으면 MANUAL: 경로별 스크립트 매핑(ISAPI/CGI/FastCGI/SSI 모듈 또는 scriptProcessor 지정 핸들러) 목록을 증적으로 남기고
#     필요 여부는 운영자가 판단
#   - 조회 실패가 있고 VULN 이 아니면 ERROR(S6)
# 사이트 루트뿐 아니라 하위 application·virtual directory 의 handlers 재정의도 확인한다(A24, Get-IisSiteConfigPaths).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-15" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-15" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$dangerExt = @(".htr", ".idc", ".stm", ".shtm", ".shtml", ".printer", ".htw", ".ida", ".idq")
$scriptModules = "IsapiModule|CgiModule|FastCgiModule|ServerSideIncludeModule"

$vuln = @(); $evid = @(); $failed = $false; $mapCount = 0
foreach ($site in $sites) {
    foreach ($cp in (Get-IisSiteConfigPaths -SiteName $site)) {
        try {
            $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $cp.PSPath -ErrorAction Stop
        } catch {
            # WEB-R7: 조회 실패를 "매핑 없음" 으로 넘기지 않는다
            $Global:IisConfigQueryFailed = $true
            $Global:IisConfigQueryError = "handlers ($($cp.Label)): $($_.Exception.Message)"
            $evid += "[$($cp.Label)] handler mapping 조회 실패: $($_.Exception.Message)"
            $failed = $true
            continue
        }
        $hit = @()
        $maps = @()
        foreach ($h in $handlers) {
            foreach ($ext in $dangerExt) {
                if ($h.path -ilike "*$ext") { $hit += "$($h.name)($($h.path))" }
            }
            if ("$($h.modules)" -match $scriptModules -or -not [string]::IsNullOrEmpty("$($h.scriptProcessor)")) {
                $maps += "$($h.name)($($h.path) -> $($h.modules))"
            }
        }
        $mapCount += $maps.Count
        $evid += "[$($cp.Label)] 대표 취약 확장자 매핑: $(if ($hit.Count -gt 0) { $hit -join ', ' } else { '없음' })"
        $evid += "[$($cp.Label)] 스크립트 매핑($($maps.Count)개): $(if ($maps.Count -gt 0) { $maps -join ', ' } else { '없음' })"
        if ($hit.Count -gt 0) { $vuln += $cp.Label }
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-15" -Status "VULN" -Detail "불필요한(대표 취약 확장자) 스크립트 매핑이 남아있는 사이트/경로: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
if ($failed) {
    return New-CheckResult -Code "WEB-15" -Status "ERROR" -Detail "일부 경로의 handler mapping 을 조회하지 못해 판정할 수 없음: $($Global:IisConfigQueryError)" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-15" -Status "MANUAL" -Detail "대표 취약 확장자 매핑은 없음 - 남은 스크립트 매핑($mapCount 개)이 업무상 필요한지 수동 확인 필요(증적의 경로별 목록 참고)" -Evidence ($evid -join "`n")

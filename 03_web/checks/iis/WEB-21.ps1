# WEB-21 (중) HTTP 리디렉션 [IIS]
# 판단 기준(가이드 원문): 양호 = HTTP 접근 시 HTTPS 리디렉션이 활성화된 경우
#                        취약 = 비활성화된 경우
# 자동화 범위: IIS 는 HTTP->HTTPS 리디렉션을 기본 내장하지 않고 SSL 설정("연결 요구") 또는
# URL Rewrite 모듈 규칙으로 구현한다. 이 도구는 (1) https 바인딩 존재 여부(WEB-20 선행 조건),
# (2) system.webServer/security/access@sslFlags 에 "Ssl"이 포함되어 평문 접근을 아예 차단하는지,
# (3) URL Rewrite 인바운드 규칙이 존재하는지만 신호로 사용한다 - 규칙의 실제 리디렉션 대상까지는
# 신뢰성 있게 판별할 수 없어 규칙이 있어도 MANUAL로 남긴다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-21" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-21" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $manual = @(); $evid = @()
foreach ($site in $sites) {
    try {
        $httpsCount = @(Get-WebBinding -Name $site -Protocol "https" -ErrorAction Stop).Count
    } catch {
        $httpsCount = 0
    }
    if ($httpsCount -eq 0) {
        $evid += "[$site] https 바인딩 없음 - HTTPS 로 리디렉션할 대상 자체가 없음"
        $vuln += $site
        continue
    }

    $sslFlags = Get-IisConfigValue -Filter "system.webServer/security/access" -Name "sslFlags" -SiteName $site
    $requiresSsl = ("$sslFlags" -split ',') -contains "Ssl"

    $rewriteRuleCount = 0
    try {
        $rewriteRuleCount = @(Get-WebConfiguration -Filter "system.webServer/rewrite/rules/rule" -PSPath "IIS:\Sites\$site" -ErrorAction Stop).Count
    } catch { $rewriteRuleCount = 0 }

    $evid += "[$site] sslFlags=$sslFlags requiresSsl=$requiresSsl rewriteRules=$rewriteRuleCount"

    if ($requiresSsl) {
        # SSL 필수 설정은 리디렉션이 아니라 HTTP 평문 접근 자체를 거부(403)하는 방식이지만,
        # 평문 통신이 이루어지지 않는다는 목적은 동일하게 달성하므로 양호로 본다.
    } elseif ($rewriteRuleCount -gt 0) {
        $manual += $site
    } else {
        $vuln += $site
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-21" -Status "VULN" -Detail "HTTPS 리디렉션/SSL 필수 설정이 없는 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
if ($manual.Count -gt 0) {
    return New-CheckResult -Code "WEB-21" -Status "MANUAL" -Detail "URL Rewrite 규칙이 존재하나 HTTPS 리디렉션 규칙인지 자동 판별 불가: $($manual -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-21" -Status "GOOD" -Detail "모든 사이트가 SSL 필수 설정으로 평문 HTTP 접근을 차단함" -Evidence ($evid -join "`n")

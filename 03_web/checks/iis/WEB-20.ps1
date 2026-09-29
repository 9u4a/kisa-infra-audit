# WEB-20 (상) SSL/TLS 활성화 [IIS]
# 판단 기준(가이드 원문): 양호 = SSL/TLS 설정이 활성화된 경우 / 취약 = 비활성화된 경우
# 자동화 범위: 사이트에 https 바인딩이 하나라도 존재하는지 확인한다. 암호화 스위트/프로토콜
# 버전(TLS 1.2 이상 등) 강도까지는 판정하지 않는다(바인딩 존재 여부만 자동화 대상).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-20" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-20" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    try {
        $bindings = Get-WebBinding -Name $site -Protocol "https" -ErrorAction Stop
    } catch {
        $bindings = @()
    }
    $evid += "[$site] https 바인딩 수 = $(@($bindings).Count)"
    if (@($bindings).Count -eq 0) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-20" -Status "VULN" -Detail "https 바인딩이 없는 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-20" -Status "GOOD" -Detail "모든 사이트에 https 바인딩이 설정되어 있음" -Evidence ($evid -join "`n")

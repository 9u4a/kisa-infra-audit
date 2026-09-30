# WEB-21 (중) HTTP 리디렉션 [IIS] — 조치 [fix: confirm]
# checks/iis/WEB-21.ps1 과 동일한 기준: https 바인딩이 있는 사이트만 sslFlags 에 Ssl 을 추가해
# HTTP 평문 접근을 차단한다(SSL 필수 설정 = 리디렉션은 아니지만 평문 통신 차단이라는 목적은
# 동일 - check 도 이를 GOOD 으로 인정). https 바인딩이 아예 없는 사이트는 인증서가 없어
# 안전하게 자동화할 수 없으므로(WEB-20과 동일한 이유) 건드리지 않는다.

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
$noHttps = @()
foreach ($site in $sites) {
    try {
        $httpsCount = @(Get-WebBinding -Name $site -Protocol "https" -ErrorAction Stop).Count
    } catch {
        $httpsCount = 0
    }
    if ($httpsCount -eq 0) {
        $noHttps += $site
        continue
    }
    $sslFlags = Get-IisConfigValue -Filter "system.webServer/security/access" -Name "sslFlags" -SiteName $site
    $requiresSsl = ("$sslFlags" -split ',') -contains "Ssl"
    if ($requiresSsl) { continue }
    $newFlags = if ($sslFlags) { "$sslFlags,Ssl" } else { "Ssl" }
    Set-FixWebConfigProperty -Filter "system.webServer/security/access" -Name "sslFlags" -Value $newFlags -PSPath "IIS:\Sites\$site"
    if ($Global:FixStatus -eq "APPLIED") { $applied += $site }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "SSL 필수(sslFlags=Ssl)로 설정해 평문 HTTP 접근을 차단한 사이트: $($applied -join ', ')$(if ($noHttps) { " / https 바인딩이 없어 건너뜀: $($noHttps -join ', ')" })"
} elseif ($noHttps.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "https 바인딩이 없어 안전하게 조치할 수 없는 사이트: $($noHttps -join ', ') - 먼저 WEB-20(SSL/TLS 활성화)을 완료할 것"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "조치가 필요한 사이트가 없음(이미 정상)"
}
$Global:FixEvidence = ""

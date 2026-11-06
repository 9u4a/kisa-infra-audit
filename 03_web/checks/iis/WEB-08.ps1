# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = 업로드/다운로드 용량을 제한한 경우 / 취약 = 제한하지 않은 경우
# 자동화 범위: system.webServer/security/requestFiltering/requestLimits@maxAllowedContentLength
# 는 IIS 7.0+ 에서 항상 기본값(30000000바이트≈28.6MB)을 가지므로 "제한 자체가 없는" 상태는
# 존재하지 않는다. 값이 비정상적으로 크게(예: 4GB 근접) 재설정된 경우만 취약으로 본다.
# 1.5.0 A24: 하위 application·virtual directory 의 web.config 재정의도 확인한다(예전에는 사이트 루트만 봄).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-08" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-08" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

# 4GB(4294967295)에 근접한 값은 사실상 "무제한" 설정으로 간주한다.
$unlimitedThreshold = 4000000000

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    foreach ($cp in (Get-IisSiteConfigPaths -SiteName $site)) {
        $maxLen = Get-IisConfigValue -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -PSPath $cp.PSPath
        $evid += "[$($cp.Label)] maxAllowedContentLength = $maxLen"
        if ($null -ne $maxLen -and [int64]$maxLen -ge $unlimitedThreshold) { $vuln += $cp.Label }
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-08" -Status "VULN" -Detail "업로드 용량 제한이 사실상 무제한으로 설정된 사이트/경로: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-08" -Status "GOOD" -Detail "모든 사이트(하위 application/virtual directory 포함)에 업로드 용량 제한이 설정되어 있음(기본값 포함)" -Evidence ($evid -join "`n")

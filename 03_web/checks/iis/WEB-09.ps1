# WEB-09 (상) 웹 서비스 프로세스 권한 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = 관리자 권한이 아닌 최소 권한 계정으로 구동 / 취약 = 관리자 권한 구동
# 자동화 범위: 사이트가 연결된 애플리케이션 풀의 processModel.identityType 을 확인한다.
# LocalSystem(로컬 시스템, 관리자 권한과 동등) 이면 취약, 그 외(ApplicationPoolIdentity·
# NetworkService·LocalService·SpecificUser)는 양호로 본다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-09" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-09" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @(); $manual = @()
foreach ($site in $sites) {
    try {
        $poolName = (Get-Website -Name $site).applicationPool
        $identityType = (Get-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -ErrorAction Stop).Value
        $evid += "[$site] AppPool=$poolName identityType=$identityType"
        if ("$identityType" -eq "LocalSystem") { $vuln += "$site($poolName)" }
    } catch {
        $manual += $site
        $evid += "[$site] 애플리케이션 풀 identity 조회 실패: $($_.Exception.Message)"
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-09" -Status "VULN" -Detail "애플리케이션 풀이 LocalSystem(관리자 권한)으로 구동 중: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
if ($manual.Count -gt 0) {
    return New-CheckResult -Code "WEB-09" -Status "MANUAL" -Detail "일부 사이트의 애플리케이션 풀 identity 를 조회하지 못함: $($manual -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-09" -Status "GOOD" -Detail "모든 사이트의 애플리케이션 풀이 최소 권한 계정으로 구동 중" -Evidence ($evid -join "`n")

# WEB-09 (상) 웹 서비스 프로세스 권한 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = 관리자 권한이 아닌 최소 권한 계정으로 구동 / 취약 = 관리자 권한 구동
# 자동화 범위: 사이트와 그 하위 application 이 쓰는 모든 애플리케이션 풀의 processModel.identityType 을 확인한다.
#   LocalSystem(관리자 권한과 동등) = 취약, ApplicationPoolIdentity·NetworkService·LocalService = 양호.
# WEB-R8: (1) 예전에는 사이트 루트 application 의 풀만 봐 하위 application 이 다른(LocalSystem) 풀을 쓰면 놓쳤다.
#   (2) SpecificUser 를 무조건 양호로 봤다 - 지정 계정이 Administrators(S-1-5-32-544)의 직접 구성원이면 취약,
#   아니면 중첩 그룹·도메인 그룹을 통한 관리자 권한 여부를 자동으로 증명할 수 없어 MANUAL.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-09" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-09" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

# Get-ItemProperty 는 속성에 따라 값 자체(문자열) 또는 ConfigurationAttribute(.Value)를 돌려준다 - 둘 다 처리
function Get-IisItemValue($x) {
    if ($null -eq $x) { return "" }
    if ($x.PSObject.Properties.Name -contains "Value") { return "$($x.Value)" }
    return "$x"
}

$vuln = @(); $evid = @(); $manual = @(); $failed = @()
$pools = @{}   # 풀 이름 → 사용하는 경로 목록
foreach ($site in $sites) {
    foreach ($cp in @(Get-IisSiteConfigPaths -SiteName $site | Where-Object { $_.IsApp })) {
        try {
            $poolName = Get-IisItemValue (Get-ItemProperty -Path $cp.PSPath -Name applicationPool -ErrorAction Stop)
            if (-not $poolName) { throw "applicationPool 값 없음" }
            if (-not $pools.ContainsKey($poolName)) { $pools[$poolName] = @() }
            $pools[$poolName] += $cp.Label
        } catch {
            $failed += $cp.Label
            $evid += "[$($cp.Label)] 애플리케이션 풀 조회 실패: $($_.Exception.Message)"
        }
    }
}

# Administrators 직접 구성원 SID(SpecificUser 판정용) - 필요할 때 1회만 조회
$adminSids = $null
foreach ($poolName in $pools.Keys) {
    $users = $pools[$poolName] -join ', '
    try {
        $identityType = Get-IisItemValue (Get-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -ErrorAction Stop)
    } catch {
        $failed += "$poolName($users)"
        $evid += "[풀 $poolName] identity 조회 실패: $($_.Exception.Message)"
        continue
    }
    if ($identityType -eq "LocalSystem") {
        $vuln += "$poolName($users)"
        $evid += "[풀 $poolName] identityType=LocalSystem 사용 경로: $users"
        continue
    }
    if ($identityType -ne "SpecificUser") {
        $evid += "[풀 $poolName] identityType=$identityType 사용 경로: $users"
        continue
    }
    $userName = ""
    try { $userName = Get-IisItemValue (Get-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.userName -ErrorAction Stop) } catch { }
    $sid = if ($userName) { ConvertTo-SidString -Name $userName } else { $null }
    if ($null -eq $adminSids) {
        try { $adminSids = @(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-544' | ForEach-Object { $_.SID }) } catch { $adminSids = @() }
    }
    if ($sid -and $adminSids -contains $sid) {
        $vuln += "$poolName($userName)"
        $evid += "[풀 $poolName] identityType=SpecificUser userName=$userName → Administrators 직접 구성원"
    } else {
        $manual += "$poolName($userName)"
        $evid += "[풀 $poolName] identityType=SpecificUser userName=$userName SID=$sid → Administrators 직접 구성원은 아님(중첩/도메인 그룹 경유 여부는 수동 확인)"
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-09" -Status "VULN" -Detail "애플리케이션 풀이 관리자 권한(LocalSystem 또는 Administrators 구성원)으로 구동 중: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
if ($failed.Count -gt 0) {
    return New-CheckResult -Code "WEB-09" -Status "ERROR" -Detail "일부 사이트/애플리케이션 풀의 identity 를 조회하지 못함: $($failed -join ', ')" -Evidence ($evid -join "`n")
}
if ($manual.Count -gt 0) {
    return New-CheckResult -Code "WEB-09" -Status "MANUAL" -Detail "특정 계정(SpecificUser)으로 구동되는 애플리케이션 풀의 관리자 권한 여부를 수동 확인 필요: $($manual -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-09" -Status "GOOD" -Detail "모든 사이트(하위 application 포함)의 애플리케이션 풀이 최소 권한 계정으로 구동 중" -Evidence ($evid -join "`n")

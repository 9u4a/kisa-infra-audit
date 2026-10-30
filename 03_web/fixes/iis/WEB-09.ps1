# WEB-09 (상) 웹 서비스 프로세스 권한 제한 [IIS] — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# LocalSystem 으로 구동 중인 애플리케이션 풀을 ApplicationPoolIdentity(최소 권한 가상 계정)로
# 전환한다. 이 계정은 IIS 가 각 풀마다 자동으로 만들어 관리하는 전용 계정이라, 특정 사용자
# 계정을 새로 만들 필요가 없다(W-14/WEB-14 계열의 "계정 생성 필요" 문제가 아님).

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
$failed = @()   # 쓰기 실패 - 예전엔 "대상 없음(NA)"으로 덮여 원인이 사라졌다
$pools = @{}
foreach ($site in $sites) {
    try {
        $poolName = (Get-Website -Name $site).applicationPool
        if ($pools.ContainsKey($poolName)) { continue }
        $pools[$poolName] = $true
        # C-WEB09(1.4.0): identityType 은 문자열로 돌아와 .Value 가 늘 비어 LocalSystem 풀도 "대상 없음(NA)"이었다(CI 실측) - 두 형태 모두 처리
        $x = Get-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -ErrorAction Stop
        $identityType = if ($null -ne $x -and $x.PSObject.Properties.Name -contains "Value") { $x.Value } else { $x }
        if ("$identityType" -eq "LocalSystem") {
            Set-FixAppPoolIdentity -PoolName $poolName -IdentityType "ApplicationPoolIdentity"
            if ($Global:FixStatus -eq "APPLIED") { $applied += $poolName } else { $failed += "${poolName}: $($Global:FixDetail)" }
        }
    } catch { $failed += "${site}: $($_.Exception.Message)" }
}

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "애플리케이션 풀을 ApplicationPoolIdentity 로 전환: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "LocalSystem 으로 구동 중인 애플리케이션 풀이 없음(이미 정상)"
}
$Global:FixEvidence = ""

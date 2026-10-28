# PC-14 (상) 바이러스 백신 프로그램에서 제공하는 실시간 감시 기능 활성화
# 판단 기준(가이드 원문): 양호 = 실시간 감시기능 활성화 / 취약 = 미설치 또는 비활성화
# W-R11: 타사 백신을 쓰면 Defender 는 수동(Passive) 모드라 Defender 의 실시간 보호는 꺼지는 것이 정상이다 - 예전에는
# 이를 VULN 으로 냈다. 이 경우 보안 센터(SecurityCenter2)의 타사 백신 활성 상태로 판단한다(실시간 감시 세부
# 설정은 제품 콘솔 확인이 필요해 MANUAL).

$mp = $null; $mpErr = ""
try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mpErr = $_.Exception.Message }

$mode = if ($mp) { "$($mp.AMRunningMode)" } else { "" }
if ($mp -and $mp.AntivirusEnabled -and $mode -notmatch 'Passive|EDR') {
    $evidence = "AMRunningMode=$mode RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled)"
    if ($mp.RealTimeProtectionEnabled) {
        return New-CheckResult -Code "PC-14" -Status "GOOD" -Detail "Windows Defender 실시간 보호 기능이 활성화되어 있음" -Evidence $evidence
    } else {
        return New-CheckResult -Code "PC-14" -Status "VULN" -Detail "Windows Defender 실시간 보호 기능이 비활성화되어 있음" -Evidence $evidence
    }
}

$mpNote = if ($mp) { "Windows Defender: AMRunningMode=$mode AntivirusEnabled=$($mp.AntivirusEnabled) RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled)" } else { "Windows Defender 상태 조회 실패: $mpErr" }
$sc = Get-SecurityCenterProducts -Class AntiVirusProduct
$active = @($sc.Products | Where-Object { $_.Enabled })
if ($active.Count -gt 0) {
    $names = ($active | ForEach-Object { $_.Name }) -join ", "
    return New-CheckResult -Code "PC-14" -Status "MANUAL" -Detail "타사 백신($names) 이 활성화되어 있음 — 실시간 감시 활성화 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence "$mpNote`n타사 백신: $names"
}
if (-not $sc.Ok) {
    return New-CheckResult -Code "PC-14" -Status "ERROR" -Detail "Windows Defender 가 꺼져 있거나 조회에 실패했고, 보안 센터(SecurityCenter2) 조회도 실패해 실시간 감시 여부를 확인할 수 없음" -Evidence "$mpNote`nSecurityCenter2: $($sc.Error)"
}
return New-CheckResult -Code "PC-14" -Status "VULN" -Detail "실시간 감시가 활성화된 백신 프로그램을 감지하지 못함" -Evidence $mpNote

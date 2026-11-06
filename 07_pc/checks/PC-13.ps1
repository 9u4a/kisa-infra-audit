# PC-13 (상) 바이러스 백신 프로그램 설치 및 주기적 업데이트
# 판단 기준(가이드 원문): 양호 = 백신 설치 + 최신 업데이트 적용 / 취약 = 미설치 또는 업데이트 안 됨
# W-R11: 타사 백신을 쓰면 Defender 는 수동(Passive) 모드이거나 꺼진다(AntivirusEnabled=False) - 예전에는 이를
# "Defender 비활성 = VULN" 으로 냈다. 이 경우 보안 센터(SecurityCenter2)의 타사 백신을 확인해 MANUAL 로 남긴다.

$mp = $null; $mpErr = ""
# B3(W-R16 누락분): Get-MpComputerStatus(CDXML)는 Defender WMI 가 멈추면 무기한 대기한다 - 60초 제한. 시간 초과는 "Defender 없음"으로
# 타사 백신 확인으로 넘어가지 않고 ERROR(확인하지 못한 것, S6). 그 밖의 실패(Defender 미설치 등)는 기존대로 보안 센터 확인.
try { $mp = Invoke-CimCmdletWithTimeout -Command Get-MpComputerStatus -TimeoutSec 60 }
catch [System.TimeoutException] { return New-CheckResult -Code "PC-13" -Status "ERROR" -Detail "Windows Defender 상태 조회 시간 초과: $($_.Exception.Message)" }
catch { $mpErr = $_.Exception.Message }

$mode = if ($mp) { "$($mp.AMRunningMode)" } else { "" }
if ($mp -and $mp.AntivirusEnabled -and $mode -notmatch 'Passive|EDR') {
    $age = $mp.AntivirusSignatureAge
    $evidence = "Windows Defender: AMRunningMode=$mode AntivirusEnabled=$($mp.AntivirusEnabled) AntivirusSignatureAge=${age}일"
    if ($age -le 7) {
        return New-CheckResult -Code "PC-13" -Status "GOOD" -Detail "Windows Defender 백신이 설치되어 있고 최근 7일 이내 업데이트됨" -Evidence $evidence
    } else {
        return New-CheckResult -Code "PC-13" -Status "VULN" -Detail "Windows Defender $(Get-DefenderSignatureAgeText -Age $age)" -Evidence $evidence
    }
}

$mpNote = if ($mp) { "Windows Defender: AMRunningMode=$mode AntivirusEnabled=$($mp.AntivirusEnabled)" } else { "Windows Defender 상태 조회 실패: $mpErr" }
$sc = Get-SecurityCenterProducts -Class AntiVirusProduct
$active = @($sc.Products | Where-Object { $_.Enabled })
if ($active.Count -gt 0) {
    $names = ($active | ForEach-Object { $_.Name }) -join ", "
    return New-CheckResult -Code "PC-13" -Status "MANUAL" -Detail "타사 백신($names) 이 감지됨 — 최신 업데이트 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence "$mpNote`n타사 백신: $names"
}
if (-not $sc.Ok) {
    return New-CheckResult -Code "PC-13" -Status "ERROR" -Detail "Windows Defender 가 꺼져 있거나 조회에 실패했고, 보안 센터(SecurityCenter2) 조회도 실패해 백신 설치 여부를 확인할 수 없음" -Evidence "$mpNote`nSecurityCenter2: $($sc.Error)"
}
$off = ($sc.Products | ForEach-Object { "$($_.Name)(꺼짐, $($_.State))" }) -join ", "
return New-CheckResult -Code "PC-13" -Status "VULN" -Detail "활성화된 백신 프로그램을 감지하지 못함(Windows Defender 비활성/미사용$(if ($off) { ", 타사 백신 꺼짐: $off" }))" -Evidence $mpNote

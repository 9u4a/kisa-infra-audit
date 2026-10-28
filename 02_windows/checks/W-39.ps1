# W-39 (상) 백신 프로그램 업데이트
# 판단 기준(가이드 원문): 양호 = 최신 엔진 업데이트 적용, 또는 망 격리 시 절차 수립됨
#                        취약 = 최신 업데이트 미적용 또는 절차 미수립
# 자동화 범위: Windows Defender 는 서명 업데이트 경과일로 자동 판정. 타사 백신은 SecurityCenter2
#             WMI 로 제품명/활성 상태만 확인하고 서명 최신 여부는 MANUAL.
# W-R11: 타사 백신이 주 백신이면 Defender 는 수동(Passive) 모드로 바뀌어 서명 업데이트가 멈출 수 있다 - 예전에는
# 이를 VULN 으로 냈다. 수동/EDR 차단 모드면 타사 백신 기준으로 MANUAL. 서버 OS 에는 SecurityCenter2 가 없어
# 타사 백신을 확인할 수 없으므로 "백신 없음 = VULN" 으로 단정하지 않고 MANUAL 로 남긴다.

$mp = $null; $mpErr = ""
try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mpErr = $_.Exception.Message }

$mode = if ($mp) { "$($mp.AMRunningMode)" } else { "" }
$passive = ($mode -match 'Passive|EDR')
if ($mp -and -not $passive) {
    $age = $mp.AntivirusSignatureAge
    $evidence = "AMRunningMode=$mode AntivirusSignatureAge=${age}일 AntivirusEnabled=$($mp.AntivirusEnabled) RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled)"
    if ($age -le 7) {
        return New-CheckResult -Code "W-39" -Status "GOOD" -Detail "Windows Defender 백신 엔진/정의가 최근 7일 이내 업데이트됨" -Evidence $evidence
    } else {
        return New-CheckResult -Code "W-39" -Status "VULN" -Detail "Windows Defender 백신 정의 업데이트가 ${age}일간 이루어지지 않음" -Evidence $evidence
    }
}

# Defender 사용 불가 또는 수동 모드 → 타사 백신 확인
$sc = Get-SecurityCenterProducts -Class AntiVirusProduct
$mpNote = if ($mp) { "Windows Defender AMRunningMode=$mode" } else { "Windows Defender 상태 조회 실패: $mpErr" }
if ($sc.Products.Count -gt 0) {
    $names = ($sc.Products | ForEach-Object { "$($_.Name)(활성=$($_.Enabled))" }) -join ", "
    return New-CheckResult -Code "W-39" -Status "MANUAL" -Detail "타사 백신($names) 이 감지됨 — 엔진/정의 최신 업데이트 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence "$mpNote`n$names"
}
if (-not $sc.Ok) {
    return New-CheckResult -Code "W-39" -Status "MANUAL" -Detail "Windows Defender 를 사용하지 않거나 수동 모드이며, 보안 센터(SecurityCenter2, 서버 OS 미제공)로 타사 백신을 확인할 수 없음 — 설치된 백신의 업데이트 상태 수동 확인 필요" -Evidence "$mpNote`nSecurityCenter2: $($sc.Error)"
}
if ($passive) {
    return New-CheckResult -Code "W-39" -Status "MANUAL" -Detail "Windows Defender 가 수동 모드($mode)이나 보안 센터에 등록된 타사 백신이 없음 — 주 백신과 업데이트 상태 수동 확인 필요" -Evidence $mpNote
}
return New-CheckResult -Code "W-39" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함" -Evidence $mpNote

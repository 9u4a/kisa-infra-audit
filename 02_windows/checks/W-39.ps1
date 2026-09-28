# W-39 (상) 백신 프로그램 업데이트
# 판단 기준(가이드 원문): 양호 = 최신 엔진 업데이트 적용, 또는 망 격리 시 절차 수립됨
#                        취약 = 최신 업데이트 미적용 또는 절차 미수립
# 자동화 범위: Windows Defender 는 서명 업데이트 경과일로 자동 판정. 타사 백신은 SecurityCenter2
#             WMI 로 제품명/활성 상태만 확인하고 서명 최신 여부는 MANUAL.

try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $age = $mp.AntivirusSignatureAge
    $evidence = "AntivirusSignatureAge=${age}일 AntivirusEnabled=$($mp.AntivirusEnabled) RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled)"
    if ($age -le 7) {
        return New-CheckResult -Code "W-39" -Status "GOOD" -Detail "Windows Defender 백신 엔진/정의가 최근 7일 이내 업데이트됨" -Evidence $evidence
    } else {
        return New-CheckResult -Code "W-39" -Status "VULN" -Detail "Windows Defender 백신 정의 업데이트가 ${age}일간 이루어지지 않음" -Evidence $evidence
    }
} catch {
    # Defender 사용 불가 시 타사 백신 존재 여부만 확인
    try {
        $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction Stop
    } catch {
        $av = $null
    }
    if ($av) {
        $names = ($av | ForEach-Object { $_.displayName }) -join ", "
        return New-CheckResult -Code "W-39" -Status "MANUAL" -Detail "타사 백신($names) 이 감지됨 — 엔진/정의 최신 업데이트 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence $names
    } else {
        return New-CheckResult -Code "W-39" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함"
    }
}

# PC-13 (상) 바이러스 백신 프로그램 설치 및 주기적 업데이트
# 판단 기준(가이드 원문): 양호 = 백신 설치 + 최신 업데이트 적용 / 취약 = 미설치 또는 업데이트 안 됨

try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $age = $mp.AntivirusSignatureAge
    $evidence = "Windows Defender: AntivirusEnabled=$($mp.AntivirusEnabled) AntivirusSignatureAge=${age}일"
    if ($mp.AntivirusEnabled -and $age -le 7) {
        return New-CheckResult -Code "PC-13" -Status "GOOD" -Detail "Windows Defender 백신이 설치되어 있고 최근 7일 이내 업데이트됨" -Evidence $evidence
    } else {
        return New-CheckResult -Code "PC-13" -Status "VULN" -Detail "Windows Defender 백신이 비활성화되어 있거나 정의 업데이트가 ${age}일간 이루어지지 않음" -Evidence $evidence
    }
} catch {
    try {
        $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction Stop
    } catch {
        $av = $null
    }
    if ($av) {
        $names = ($av | ForEach-Object { $_.displayName }) -join ", "
        return New-CheckResult -Code "PC-13" -Status "MANUAL" -Detail "타사 백신($names) 이 감지됨 — 최신 업데이트 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence $names
    } else {
        return New-CheckResult -Code "PC-13" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함"
    }
}

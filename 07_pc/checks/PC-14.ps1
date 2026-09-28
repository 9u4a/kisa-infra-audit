# PC-14 (상) 바이러스 백신 프로그램에서 제공하는 실시간 감시 기능 활성화
# 판단 기준(가이드 원문): 양호 = 실시간 감시기능 활성화 / 취약 = 미설치 또는 비활성화

try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $evidence = "RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled)"
    if ($mp.RealTimeProtectionEnabled) {
        return New-CheckResult -Code "PC-14" -Status "GOOD" -Detail "Windows Defender 실시간 보호 기능이 활성화되어 있음" -Evidence $evidence
    } else {
        return New-CheckResult -Code "PC-14" -Status "VULN" -Detail "Windows Defender 실시간 보호 기능이 비활성화되어 있음" -Evidence $evidence
    }
} catch {
    try {
        $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction Stop
    } catch {
        $av = $null
    }
    if ($av) {
        $names = ($av | ForEach-Object { $_.displayName }) -join ", "
        return New-CheckResult -Code "PC-14" -Status "MANUAL" -Detail "타사 백신($names) 이 감지됨 — 실시간 감시 활성화 여부는 해당 제품 콘솔에서 수동 확인 필요" -Evidence $names
    } else {
        return New-CheckResult -Code "PC-14" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함"
    }
}

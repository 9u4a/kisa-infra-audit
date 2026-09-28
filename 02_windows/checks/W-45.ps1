# W-45 (상) 백신 프로그램 설치
# 판단 기준(가이드 원문): 양호 = 바이러스 백신 프로그램이 설치된 경우 / 취약 = 미설치

try {
    $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction Stop
} catch {
    $av = $null
}

if ($av) {
    $names = ($av | ForEach-Object { $_.displayName }) -join ", "
    return New-CheckResult -Code "W-45" -Status "GOOD" -Detail "백신 프로그램이 설치되어 있음: $names" -Evidence $names
}

# SecurityCenter2 조회 실패 시 Defender 상태로 대체 확인
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.AMServiceEnabled) {
        return New-CheckResult -Code "W-45" -Status "GOOD" -Detail "Windows Defender 백신이 설치·활성화되어 있음" -Evidence "AMServiceEnabled=$($mp.AMServiceEnabled)"
    }
} catch {}

return New-CheckResult -Code "W-45" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함"

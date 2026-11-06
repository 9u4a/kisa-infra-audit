# W-45 (상) 백신 프로그램 설치
# 판단 기준(가이드 원문): 양호 = 바이러스 백신 프로그램이 설치된 경우 / 취약 = 미설치

try {
    $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -OperationTimeoutSec 30 -ErrorAction Stop
} catch {
    $av = $null
}

if ($av) {
    $names = ($av | ForEach-Object { $_.displayName }) -join ", "
    return New-CheckResult -Code "W-45" -Status "GOOD" -Detail "백신 프로그램이 설치되어 있음: $names" -Evidence $names
}

# SecurityCenter2 조회 실패 시 Defender 상태로 대체 확인
# B3(W-R16 누락분): Get-MpComputerStatus(CDXML)는 Defender WMI 가 멈추면 무기한 대기한다 - 60초 제한, 시간 초과는 "미설치"(VULN)가
# 아니라 확인하지 못한 것이므로 ERROR(S6). 그 밖의 실패(Defender 미설치 등)는 기존대로 미설치로 본다.
try {
    $mp = Invoke-CimCmdletWithTimeout -Command Get-MpComputerStatus -TimeoutSec 60
    if ($mp.AMServiceEnabled) {
        return New-CheckResult -Code "W-45" -Status "GOOD" -Detail "Windows Defender 백신이 설치·활성화되어 있음" -Evidence "AMServiceEnabled=$($mp.AMServiceEnabled)"
    }
} catch [System.TimeoutException] {
    return New-CheckResult -Code "W-45" -Status "ERROR" -Detail "보안 센터에서 백신을 찾지 못했고 Windows Defender 상태 조회는 시간 초과: $($_.Exception.Message)"
} catch { $null = $_ }

return New-CheckResult -Code "W-45" -Status "VULN" -Detail "설치된 백신 프로그램을 감지하지 못함"

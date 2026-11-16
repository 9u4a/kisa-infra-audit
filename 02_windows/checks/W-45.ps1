# W-45 (상) 백신 프로그램 설치
# 판단 기준(가이드 원문): 양호 = 바이러스 백신 프로그램이 설치된 경우 / 취약 = 미설치
# 판정 분기는 lib/Common.psm1 Get-AntivirusInstallVerdict(V-R8: 보안 센터가 없는 서버 OS 에서 Defender 가 꺼져 있으면
# 타사 백신을 확인할 수 없어 VULN 이 아니라 MANUAL, 클라이언트에서 보안 센터 조회 실패는 ERROR).

$scOk = $true; $scErr = ""; $scNames = @()
try {
    $av = @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -OperationTimeoutSec 30 -ErrorAction Stop)
    $scNames = @($av | ForEach-Object { "$($_.displayName)" })
} catch {
    $scOk = $false; $scErr = $_.Exception.Message
}

# B3(W-R16 누락분): Get-MpComputerStatus(CDXML)는 Defender WMI 가 멈추면 무기한 대기한다 - 60초 제한, 시간 초과는 "미설치"가
# 아니라 확인하지 못한 것이므로 ERROR(S6). 보안 센터에 백신이 등록돼 있으면 Defender 는 보지 않는다.
$mpEnabled = $null; $mpErr = ""
if ($scNames.Count -eq 0) {
    try {
        $mp = Invoke-CimCmdletWithTimeout -Command Get-MpComputerStatus -TimeoutSec 60
        $mpEnabled = [bool]$mp.AMServiceEnabled
    } catch [System.TimeoutException] {
        return New-CheckResult -Code "W-45" -Status "ERROR" -Detail "보안 센터에서 백신을 찾지 못했고 Windows Defender 상태 조회는 시간 초과: $($_.Exception.Message)"
    } catch { $mpErr = $_.Exception.Message }
}

$isServer = $false
if (-not $scOk -and $scNames.Count -eq 0) {
    try {
        $isServer = ((Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 30 -ErrorAction Stop).ProductType -ne 1)
    } catch {
        return New-CheckResult -Code "W-45" -Status "ERROR" -Detail "보안 센터 조회 실패, OS 유형(Win32_OperatingSystem) 조회도 실패: $($_.Exception.Message)" -Evidence "SecurityCenter2: $scErr"
    }
}

$v = Get-AntivirusInstallVerdict -ScOk $scOk -ScNames $scNames -ScError $scErr -MpEnabled $mpEnabled -MpError $mpErr -IsServer $isServer
return New-CheckResult -Code "W-45" -Status $v.Status -Detail $v.Detail -Evidence $v.Evidence

# PC-13 (상) 바이러스 백신 프로그램 설치 및 주기적 업데이트 [fix: auto]
# 02_windows/fixes/W-39.ps1 과 동일한 이유로 Windows Defender 서명 갱신만 자동화 대상이다
# (백신 자체의 설치는 자동화 대상이 아님).

try {
    Update-MpSignature -ErrorAction Stop
    Start-Sleep -Seconds 2
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.AntivirusEnabled -and $mp.AntivirusSignatureAge -le 7) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "Windows Defender 서명 업데이트 실행함(AntivirusSignatureAge=$($mp.AntivirusSignatureAge)일)"
        $Global:FixEvidence = ""
    } else {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "서명 업데이트를 실행했으나 기준을 충족하지 못함(AntivirusEnabled=$($mp.AntivirusEnabled), AntivirusSignatureAge=$($mp.AntivirusSignatureAge)일)"
        $Global:FixEvidence = ""
    }
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Windows Defender 를 사용할 수 없거나 서명 업데이트 실패(타사 백신이거나 백신 미설치 - 설치 자체는 자동화 대상이 아님): $($_.Exception.Message)"
    $Global:FixEvidence = ""
}

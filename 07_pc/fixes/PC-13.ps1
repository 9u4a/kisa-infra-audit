# PC-13 (상) 바이러스 백신 프로그램 설치 및 주기적 업데이트 [fix: auto]
# 원복: 불가 — 백신 서명 업데이트는 되돌리지 않는다(이전 서명으로 되돌릴 이유·경로가 없음, 운영 안전 기준 F4 로 사전 고지)
# 02_windows/fixes/W-39.ps1 과 동일한 이유로 Windows Defender 서명 갱신만 자동화 대상이다
# (백신 자체의 설치는 자동화 대상이 아님).

# F-W39(1.4.0): 원복 불가를 정직하게 기록 - 예전에는 표시가 없어 fix.ps1 -Rollback 이 "원복 완료"로 보이고 판정만 달라졌다
# (fix_safety CI run 41041494009: 기준 VULN → 원복 후 GOOD)
try {
    Update-MpSignature -ErrorAction Stop
    # 업데이트가 실제로 실행된 뒤에만 표시(실패해 바뀐 것이 없으면 원복 불가로 보고하지 않음)
    Register-FixNoRollback -Reason "백신 서명 업데이트 - 되돌리지 않음(이전 서명으로 복구할 경로 없음)"
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

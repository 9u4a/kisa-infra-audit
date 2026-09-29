# PC-14 (상) 바이러스 백신 프로그램에서 제공하는 실시간 감시 기능 활성화 [fix: auto]

try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.RealTimeProtectionEnabled) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "Windows Defender 실시간 보호 기능을 활성화함"
    } else {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "Set-MpPreference 를 실행했으나 여전히 비활성화 상태임(그룹 정책으로 강제 비활성화되어 있을 수 있음)"
    }
    $Global:FixEvidence = ""
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Windows Defender 를 사용할 수 없음(타사 백신이거나 백신 미설치): $($_.Exception.Message)"
    $Global:FixEvidence = ""
}

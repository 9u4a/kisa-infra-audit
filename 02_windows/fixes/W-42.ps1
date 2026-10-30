# W-42 (하) 이벤트 로그 관리 설정 [fix: auto]
# 원복: 불가 — 이벤트 로그 최대 크기는 자동 원복 경로 없음(변경 전 값은 changes.log)
# checks/W-42.ps1: 양호 = Application/Security/System 로그 최대 크기 10,240KB 이상.
# 채널 최대 크기는 백업 없이 값을 직접 바꾸므로, 변경 전 값을 changes.log 증적에 남기고
# 표준 Restore-FixItem 대상(레지스트리/서비스/ACL/공유)에는 포함하지 않는다.

$logs = @("Application", "Security", "System")
$before = @()
$applied = @()
$failed = @()

# 원복 경로가 없는 자원 - 원복 시 "원복 불가"로 정직하게 보고되도록 변경 직전에 표시(lib/Common.psm1)
Register-FixNoRollback -Reason "이벤트 로그 최대 크기(채널 설정) - 변경 전 크기는 changes.log 상세 참고"
foreach ($logName in $logs) {
    try {
        $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
        $before += "$logName : $($log.MaximumSizeInBytes)bytes"
        if (($log.MaximumSizeInBytes / 1KB) -lt 10240) {
            # F-W42(1.4.0): Limit-EventLog 는 이 OS(Server 2025) 에서 채널 최대 크기를 바꾸지 못했다(오류 없이 그대로 - 양방향 케이스
            # 조치 검증과 케이스 준비 실측, CI run 40981289087/41009844085). 진단이 읽는 채널 설정(EventLogConfiguration, wevtutil sl /ms 와
            # 같은 API)으로 바꾸고 다시 읽어 확인한다.
            $cfg = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration($logName)
            $cfg.MaximumSizeInBytes = 10240KB
            $cfg.SaveChanges()
            if ((Get-WinEvent -ListLog $logName -ErrorAction Stop).MaximumSizeInBytes -lt 10240KB) { throw "변경 후에도 10,240KB 미만" }
            $applied += $logName
        }
    } catch {
        $failed += $logName
    }
}

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 로그 크기 설정 실패: $($failed -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "로그 최대 크기를 10,240KB로 설정: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "이미 모든 로그가 기준을 충족함"
}
$Global:FixEvidence = "변경 전:`n" + ($before -join "`n")

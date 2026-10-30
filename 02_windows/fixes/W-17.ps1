# W-17 (상) 하드디스크 기본 공유 제거 [fix: confirm]
# 원복: 일부 — 레지스트리는 되돌리지만 중지한 기본 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김(실행 중 삭제가 거부되면 조치가 Server 서비스를 재시작 - SMB 연결 끊김)
# checks/W-17.ps1: 양호 = AutoShareServer=0 이며 기본(관리용) 공유가 존재하지 않는 경우.
# 재시작 후에도 유지되도록 레지스트리를 먼저 설정하고(백업/원복 가능), 현재 활성 중인 기본
# 공유는 즉시 효과를 위해 별도로 제거한다(관리용 공유 재생성은 원복 대상에 포함하지 않음 -
# 다음 재부팅 시 레지스트리 값에 따라 정상적으로 결정됨).

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareServer" -Value 0 -Type DWord

# 원복 경로가 없는 자원 - 원복 시 "원복 불가"로 정직하게 보고되도록 변경 직전에 표시(lib/Common.psm1)
Register-FixNoRollback -Reason "즉시 삭제한 기본 공유(ADMIN$/C$ 등) - 레지스트리는 원복되지만 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김"
# F-W17(1.4.0): 삭제 실패를 숨기지 않는다 - 거부되면 Server 서비스 재시작으로 중지하고, 그래도 남으면 ERROR(재검증 전에 정직하게)
try {
    $r = Remove-FixDefaultShares
    if ($r.Removed.Count -gt 0) { $Global:FixDetail = "$($Global:FixDetail); 기본 공유 중지: $($r.Removed -join ', ')$(if ($r.Restarted) { ' (실행 중 삭제가 거부되어 Server 서비스 재시작)' })" }
    if ($r.Remaining.Count -gt 0) { $Global:FixStatus = "ERROR"; $Global:FixDetail = "$($Global:FixDetail); 기본 공유를 중지하지 못함: $($r.Remaining -join ', ')" }
} catch {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "$($Global:FixDetail); 기본 공유 중지 실패: $($_.Exception.Message)"
}

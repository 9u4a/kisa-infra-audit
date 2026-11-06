# W-18 (상) 불필요한 서비스 제거
# 판단 기준(가이드 원문): 양호 = 일반적으로 불필요한 서비스가 중지된 경우 / 취약 = 구동 중인 경우
# 참고: 가이드에 나열된 서비스(Alerter, Messenger, ClipBook 등) 상당수는 최신 Windows Server에
#      더 이상 존재하지 않는다. 현재 버전에도 남아있는 대표 서비스명만 자동 판정한다.
# A8: 예전에는 Status≠Running 이면 "중지"로 봤다. 대상 서비스 다수(RemoteRegistry·SSDPSRV·WerSvc 등)는 트리거 시작·유휴 시
# 자동 중지라 시작 유형이 자동/수동이면 진단 순간에만 Stopped 다. 가이드 조치("서비스 중지 후 '사용 안 함' 설정")대로
# 실행 중이 아니고 시작 유형이 사용 안 함(Disabled)일 때만 중지로 본다(guide.json deviation).

$targets = @(
    @{ Name = "RemoteRegistry"; Label = "Remote Registry" },
    @{ Name = "SSDPSRV";        Label = "SSDP Discovery (UPnP)" },
    @{ Name = "upnphost";       Label = "UPnP Device Host" },
    @{ Name = "simptcp";        Label = "Simple TCP/IP Services" },
    @{ Name = "Browser";        Label = "Computer Browser" },
    @{ Name = "WerSvc";         Label = "Windows Error Reporting" }
)

$running = @()
$startable = @()
$evidence = @()
$unverified = @()
foreach ($t in $targets) {
    # 조회 실패(비관리자 배치 실행 등)를 "서비스 없음"으로 읽지 않는다(CI 실측: 비관리자 실행에서 VULN→NA)
    try { $svc = Get-ServiceChecked -Name $t.Name }
    catch { $unverified += $t.Label; $evidence += "$($t.Label) ($($t.Name)): 조회 실패 - $($_.Exception.Message)"; continue }
    if (-not $svc) { continue }
    $evidence += "$($t.Label) ($($t.Name)): $($svc.Status) / 시작 유형 $($svc.StartType)"
    if ("$($svc.Status)" -eq "Running") { $running += $t.Label }
    elseif ("$($svc.StartType)" -ne "Disabled") { $startable += "$($t.Label)(중지, 시작 유형 $($svc.StartType))" }
}

if ($running.Count -eq 0 -and $startable.Count -eq 0 -and $unverified.Count -gt 0) {
    return New-CheckResult -Code "W-18" -Status "ERROR" -Detail ("서비스 상태를 조회하지 못함: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
}
if ($evidence.Count -eq 0) {
    return New-CheckResult -Code "W-18" -Status "NA" -Detail "점검 대상 서비스(가이드 예시 목록)가 이 시스템에 존재하지 않음"
}

if ($running.Count -eq 0 -and $startable.Count -eq 0) {
    return New-CheckResult -Code "W-18" -Status "GOOD" -Detail "점검 대상 불필요 서비스가 모두 중지·사용 안 함으로 설정되어 있음" -Evidence ($evidence -join "`n")
}
$parts = @()
if ($running.Count -gt 0) { $parts += "구동 중인 불필요 서비스: " + ($running -join ", ") }
if ($startable.Count -gt 0) { $parts += "중지 상태이나 사용 안 함이 아니어서 요청·재부팅 시 시작될 수 있는 서비스: " + ($startable -join ", ") }
return New-CheckResult -Code "W-18" -Status "VULN" -Detail ($parts -join " / ") -Evidence ($evidence -join "`n")

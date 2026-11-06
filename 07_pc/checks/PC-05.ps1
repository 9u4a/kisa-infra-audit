# PC-05 (상) 항목의 불필요한 서비스 제거
# 판단 기준(가이드 원문): 양호 = 일반적으로 불필요한 서비스가 중지된 경우 / 취약 = 중지되지 않은 경우
# 참고: 가이드 목록(Alerter, Messenger, ClipBook 등) 대부분은 최신 Windows 에 존재하지 않는다.
# A8: 예전에는 Status≠Running 이면 "중지"로 봤다. 대상 서비스 다수(RemoteRegistry·SSDPSRV·WerSvc 등)는 트리거 시작·유휴 시
# 자동 중지라 시작 유형이 자동/수동이면 진단 순간에만 Stopped 이고 요청이 오면 다시 켜진다(= 중지되지 않음). 실행 중이 아니고
# 시작 유형이 사용 안 함(Disabled)일 때만 중지로 본다(guide.json deviation). 서비스 조회 실패는 "없음"이 아니라 ERROR(S6).

$targets = @(
    @{ Name = "RemoteRegistry"; Label = "Remote Registry" },
    @{ Name = "SSDPSRV";        Label = "SSDP Discovery (UPnP)" },
    @{ Name = "upnphost";       Label = "UPnP Device Host" },
    @{ Name = "WerSvc";         Label = "Windows Error Reporting" },
    @{ Name = "TapiSrv";        Label = "Telephony" },
    @{ Name = "Fax";            Label = "Fax" }
)

$running = @()
$startable = @()
$evidence = @()
$unverified = @()
foreach ($t in $targets) {
    try { $svc = Get-ServiceChecked -Name $t.Name }
    catch { $unverified += $t.Label; $evidence += "$($t.Label) ($($t.Name)): 조회 실패 - $($_.Exception.Message)"; continue }
    if (-not $svc) { continue }
    $evidence += "$($t.Label) ($($t.Name)): $($svc.Status) / 시작 유형 $($svc.StartType)"
    if ("$($svc.Status)" -eq "Running") { $running += $t.Label }
    elseif ("$($svc.StartType)" -ne "Disabled") { $startable += "$($t.Label)(중지, 시작 유형 $($svc.StartType))" }
}

if ($running.Count -eq 0 -and $startable.Count -eq 0 -and $unverified.Count -gt 0) {
    return New-CheckResult -Code "PC-05" -Status "ERROR" -Detail ("서비스 상태를 조회하지 못함: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
}
if ($evidence.Count -eq 0) {
    return New-CheckResult -Code "PC-05" -Status "NA" -Detail "점검 대상 서비스(가이드 예시 목록)가 이 시스템에 존재하지 않음"
}

if ($running.Count -eq 0 -and $startable.Count -eq 0) {
    return New-CheckResult -Code "PC-05" -Status "GOOD" -Detail "점검 대상 불필요 서비스가 모두 중지·사용 안 함으로 설정되어 있음" -Evidence ($evidence -join "`n")
}
$parts = @()
if ($running.Count -gt 0) { $parts += "구동 중인 불필요 서비스: " + ($running -join ", ") }
if ($startable.Count -gt 0) { $parts += "중지 상태이나 사용 안 함이 아니어서 요청·재부팅 시 시작될 수 있는 서비스: " + ($startable -join ", ") }
return New-CheckResult -Code "PC-05" -Status "VULN" -Detail ($parts -join " / ") -Evidence ($evidence -join "`n")

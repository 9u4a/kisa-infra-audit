# PC-05 (상) 항목의 불필요한 서비스 제거
# 판단 기준(가이드 원문): 양호 = 일반적으로 불필요한 서비스가 중지된 경우 / 취약 = 구동 중인 경우
# 참고: 가이드 목록(Alerter, Messenger, ClipBook 등) 대부분은 최신 Windows 에 존재하지 않는다.

$targets = @(
    @{ Name = "RemoteRegistry"; Label = "Remote Registry" },
    @{ Name = "SSDPSRV";        Label = "SSDP Discovery (UPnP)" },
    @{ Name = "upnphost";       Label = "UPnP Device Host" },
    @{ Name = "WerSvc";         Label = "Windows Error Reporting" },
    @{ Name = "TapiSrv";        Label = "Telephony" },
    @{ Name = "Fax";            Label = "Fax" }
)

$running = @()
$evidence = @()
foreach ($t in $targets) {
    $svc = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    $evidence += "$($t.Label) ($($t.Name)): $($svc.Status)"
    if ($svc.Status -eq "Running") { $running += $t.Label }
}

if ($evidence.Count -eq 0) {
    return New-CheckResult -Code "PC-05" -Status "NA" -Detail "점검 대상 서비스(가이드 예시 목록)가 이 시스템에 존재하지 않음"
}

if ($running.Count -eq 0) {
    return New-CheckResult -Code "PC-05" -Status "GOOD" -Detail "점검 대상 불필요 서비스가 모두 중지되어 있음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "PC-05" -Status "VULN" -Detail ("구동 중인 불필요 서비스: " + ($running -join ", ")) -Evidence ($evidence -join "`n")
}

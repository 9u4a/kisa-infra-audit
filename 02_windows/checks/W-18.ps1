# W-18 (상) 불필요한 서비스 제거
# 판단 기준(가이드 원문): 양호 = 일반적으로 불필요한 서비스가 중지된 경우 / 취약 = 구동 중인 경우
# 참고: 가이드에 나열된 서비스(Alerter, Messenger, ClipBook 등) 상당수는 최신 Windows Server에
#      더 이상 존재하지 않는다. 현재 버전에도 남아있는 대표 서비스명만 자동 판정한다.

$targets = @(
    @{ Name = "RemoteRegistry"; Label = "Remote Registry" },
    @{ Name = "SSDPSRV";        Label = "SSDP Discovery (UPnP)" },
    @{ Name = "upnphost";       Label = "UPnP Device Host" },
    @{ Name = "simptcp";        Label = "Simple TCP/IP Services" },
    @{ Name = "Browser";        Label = "Computer Browser" },
    @{ Name = "WerSvc";         Label = "Windows Error Reporting" }
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
    return New-CheckResult -Code "W-18" -Status "NA" -Detail "점검 대상 서비스(가이드 예시 목록)가 이 시스템에 존재하지 않음"
}

if ($running.Count -eq 0) {
    return New-CheckResult -Code "W-18" -Status "GOOD" -Detail "점검 대상 불필요 서비스가 모두 중지되어 있음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-18" -Status "VULN" -Detail ("구동 중인 불필요 서비스: " + ($running -join ", ")) -Evidence ($evidence -join "`n")
}

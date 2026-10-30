# W-25 (상) DNS Zone Transfer 설정 [fix: confirm]
# 원복: 불가 — DNS 영역 전송 설정(WMI)은 자동 원복 경로 없음(변경 전 값은 changes.log)
# checks/W-25.ps1: 취약 = SecureSecondaries=0(모든 서버에 영역 전송 허용)인 영역이 존재.
# 특정 보조 서버로 제한하려면 그 서버 목록을 알아야 하므로(스크립트가 안전하게 추정 불가),
# 가장 안전한 값인 3(전송 안 함)으로 설정한다 - 실제로 보조 DNS 서버 운영 중이라면 이 조치로
# 영역 전송이 끊기므로 confirm 등급으로 사람이 확인한다.
#
# MicrosoftDNS_Zone 은 CIM(WMI) 클래스라 레지스트리 헬퍼로 백업/원복할 수 없다 - 이 항목은
# Restore-FixItem 의 표준 원복 대상에 포함되지 않는 알려진 한계다(02_windows/CLAUDE.md 참고).

$svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    $Global:FixStatus = "NA"; $Global:FixDetail = "DNS 서버 서비스를 사용하지 않음"; $Global:FixEvidence = ""
    return
}

try {
    $zones = Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_Zone" -ErrorAction Stop |
        Where-Object { $_.SecureSecondaries -eq 0 }
} catch {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MicrosoftDNS_Zone 조회 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
    return
}

if (-not $zones) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "Zone Transfer 가 무제한으로 설정된 영역이 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
# 원복 경로가 없는 자원 - 원복 시 "원복 불가"로 정직하게 보고되도록 변경 직전에 표시(lib/Common.psm1)
if (@($zones).Count -gt 0) { Register-FixNoRollback -Reason "DNS 영역 영역 전송 설정(SecureSecondaries, WMI) - 변경 전 값은 changes.log 상세 참고" }
# F-W25(1.4.0): SecureSecondaries 는 속성 대입 + Put() 으로 바뀌지 않는다(예외도 없이 그대로) - 예전에는 그래도 APPLIED 로 보고했다
# (양방향 케이스의 조치 검증: 조치 후 재진단 VULN). MicrosoftDNS_Zone.ResetSecondaries 로 바꾸고(보조 서버·알림 설정은 유지),
# 다시 읽어 실제로 3 이 된 영역만 적용으로 센다.
$failedZones = @()
foreach ($z in $zones) {
    try {
        [void]$z.ResetSecondaries([string[]]@($z.SecondaryServers), [uint32]3, [string[]]@($z.NotifyServers), [uint32]$z.Notify)
        $now = Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_Zone" -Filter "Name='$($z.Name)'" -ErrorAction Stop
        if ($now.SecureSecondaries -eq 3) { $applied += $z.Name } else { $failedZones += "$($z.Name)(SecureSecondaries=$($now.SecureSecondaries))" }
    } catch { $failedZones += "$($z.Name)($($_.Exception.Message))" }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "영역 Zone Transfer 를 '전송 안 함'(3)으로 설정: $($applied -join ', ')"
    $Global:FixEvidence = ""
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "영역 SecureSecondaries 설정 실패: $($failedZones -join ', ')"
    $Global:FixEvidence = ""
}

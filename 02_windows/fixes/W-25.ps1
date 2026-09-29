# W-25 (상) DNS Zone Transfer 설정 [fix: confirm]
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
foreach ($z in $zones) {
    try {
        $z.SecureSecondaries = 3
        [void]$z.Put()
        $applied += $z.Name
    } catch { }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "영역 Zone Transfer 를 '전송 안 함'(3)으로 설정: $($applied -join ', ')"
    $Global:FixEvidence = ""
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "영역 SecureSecondaries 설정 실패"
    $Global:FixEvidence = ""
}

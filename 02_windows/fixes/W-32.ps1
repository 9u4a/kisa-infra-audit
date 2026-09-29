# W-32 (중) DNS 서비스 구동 점검 (동적 업데이트 설정) [fix: auto]
# checks/W-32.ps1: 취약 = AllowUpdate != 0 인 영역 존재. 가이드 권고값(0=없음)으로 설정한다.
# W-25 와 동일하게 MicrosoftDNS_Zone 은 CIM(WMI) 클래스라 Restore-FixItem 표준 원복 대상에
# 포함되지 않는다(02_windows/CLAUDE.md 참고).

$svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    $Global:FixStatus = "NA"; $Global:FixDetail = "DNS 서버 서비스를 사용하지 않음"; $Global:FixEvidence = ""
    return
}

try {
    $zones = Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_Zone" -ErrorAction Stop |
        Where-Object { $_.AllowUpdate -ne 0 }
} catch {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MicrosoftDNS_Zone 조회 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
    return
}

if (-not $zones) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "동적 업데이트가 설정된 영역이 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($z in $zones) {
    try {
        $z.AllowUpdate = 0
        [void]$z.Put()
        $applied += $z.Name
    } catch { }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "영역 동적 업데이트를 '없음'(0)으로 설정: $($applied -join ', ')"
    $Global:FixEvidence = ""
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "영역 AllowUpdate 설정 실패"
    $Global:FixEvidence = ""
}

# W-64 (중) 윈도우 방화벽 설정
# 판단 기준(가이드 원문): 양호 = Windows 방화벽 "사용" / 취약 = "사용 안 함"

try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-64" -Status "ERROR" -Detail "Get-NetFirewallProfile 실행 실패: $($_.Exception.Message)"
}

$disabled = $profiles | Where-Object { -not $_.Enabled }
$evidence = ($profiles | ForEach-Object { "$($_.Name): Enabled=$($_.Enabled)" }) -join "`n"

if ($disabled.Count -eq 0) {
    return New-CheckResult -Code "W-64" -Status "GOOD" -Detail "모든 방화벽 프로필(도메인/개인/공용)이 사용으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-64" -Status "VULN" -Detail ("방화벽이 비활성화된 프로필 존재: " + (($disabled | ForEach-Object { $_.Name }) -join ", ")) -Evidence $evidence
}

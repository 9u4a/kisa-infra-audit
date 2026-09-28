# PC-15 (상) OS에서 제공하는 침입차단 기능 활성화
# 판단 기준(가이드 원문): 양호 = Windows 방화벽 사용 또는 기타 유·무료 방화벽 사용
#                        취약 = Windows 방화벽 미사용 및 기타 방화벽도 미사용

$wfQueryOk = $false
try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
    $disabled = $profiles | Where-Object { -not $_.Enabled }
    $wfEvidence = ($profiles | ForEach-Object { "$($_.Name): Enabled=$($_.Enabled)" }) -join "`n"
    $wfQueryOk = $true
} catch {
    $disabled = $null
    $wfEvidence = "Get-NetFirewallProfile 조회 실패"
}

# 주의: PowerShell 에서 Where-Object 결과가 없으면 $disabled 는 $null 이 되지만, $null.Count 는
# 안전하게 0 을 반환하므로 "-ne $null" 같은 방어적 가드를 추가로 걸지 않는다(걸면 정상 케이스에서
# 오히려 오탐이 발생함 — 실제로 겪은 버그).
if ($wfQueryOk -and $disabled.Count -eq 0) {
    return New-CheckResult -Code "PC-15" -Status "GOOD" -Detail "Windows 방화벽의 모든 프로필이 사용으로 설정됨" -Evidence $wfEvidence
}

try {
    $fw = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "FirewallProduct" -ErrorAction Stop
} catch {
    $fw = $null
}

if ($fw) {
    $names = ($fw | ForEach-Object { $_.displayName }) -join ", "
    return New-CheckResult -Code "PC-15" -Status "GOOD" -Detail "타사 방화벽($names) 이 활성화되어 있음" -Evidence "$wfEvidence`n타사 방화벽: $names"
} else {
    return New-CheckResult -Code "PC-15" -Status "VULN" -Detail "Windows 방화벽이 비활성화되어 있고 타사 방화벽도 감지되지 않음" -Evidence $wfEvidence
}

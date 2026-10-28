# PC-15 (상) OS에서 제공하는 침입차단 기능 활성화
# 판단 기준(가이드 원문): 양호 = Windows 방화벽 사용 또는 기타 유·무료 방화벽 사용
#                        취약 = Windows 방화벽 미사용 및 기타 방화벽도 미사용
# W-R4: (1) 로컬 저장소가 아니라 실제 적용 중인 값(ActiveStore = 로컬 + GPO 병합)으로 판정한다. (2) 보안 센터에
# 등록만 되어 있고 꺼진 타사 방화벽을 예전에는 "활성"으로 봤다 - productState 의 활성 비트를 확인한다.
# (3) 조회에 실패해 확인하지 못한 경우 VULN 이 아니라 ERROR. W-R16: CDXML cmdlet 시간 제한.

$wfQueryOk = $false
try {
    $profiles = @(Invoke-CimCmdletWithTimeout -Command Get-NetFirewallProfile -Parameters @{ PolicyStore = 'ActiveStore' })
    $disabled = $profiles | Where-Object { "$($_.Enabled)" -ne "True" }
    $wfEvidence = "적용 중인 정책(ActiveStore)`n" + (($profiles | ForEach-Object { "$($_.Name): Enabled=$($_.Enabled)" }) -join "`n")
    $wfQueryOk = ($profiles.Count -gt 0)
} catch {
    $disabled = $null
    $wfEvidence = "Get-NetFirewallProfile 조회 실패: $($_.Exception.Message)"
}

# 주의: PowerShell 에서 Where-Object 결과가 없으면 $disabled 는 $null 이 되지만, $null.Count 는
# 안전하게 0 을 반환하므로 "-ne $null" 같은 방어적 가드를 추가로 걸지 않는다(걸면 정상 케이스에서
# 오히려 오탐이 발생함 — 실제로 겪은 버그).
if ($wfQueryOk -and $disabled.Count -eq 0) {
    return New-CheckResult -Code "PC-15" -Status "GOOD" -Detail "Windows 방화벽의 모든 프로필이 사용으로 설정됨" -Evidence $wfEvidence
}

$sc = Get-SecurityCenterProducts -Class FirewallProduct
$active = @($sc.Products | Where-Object { $_.Enabled })
$scEvidence = if ($sc.Ok) { "타사 방화벽: " + $(if ($sc.Products.Count -gt 0) { ($sc.Products | ForEach-Object { "$($_.Name)(활성=$($_.Enabled), $($_.State))" }) -join ", " } else { "없음" }) } else { "SecurityCenter2 조회 실패: $($sc.Error)" }

if ($active.Count -gt 0) {
    $names = ($active | ForEach-Object { $_.Name }) -join ", "
    return New-CheckResult -Code "PC-15" -Status "GOOD" -Detail "타사 방화벽($names) 이 활성화되어 있음" -Evidence "$wfEvidence`n$scEvidence"
}
if (-not $wfQueryOk -or -not $sc.Ok) {
    return New-CheckResult -Code "PC-15" -Status "ERROR" -Detail "Windows 방화벽 또는 보안 센터(타사 방화벽) 상태를 조회하지 못해 판정할 수 없음" -Evidence "$wfEvidence`n$scEvidence"
}
return New-CheckResult -Code "PC-15" -Status "VULN" -Detail "Windows 방화벽이 비활성화되어 있고 활성화된 타사 방화벽도 감지되지 않음" -Evidence "$wfEvidence`n$scEvidence"

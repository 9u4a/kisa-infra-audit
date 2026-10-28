# W-64 (중) 윈도우 방화벽 설정
# 판단 기준(가이드 원문): 양호 = Windows 방화벽 "사용" / 취약 = "사용 안 함"
# W-R4: Get-NetFirewallProfile 의 기본 조회 대상은 로컬 저장소(PersistentStore)라 그룹 정책으로 끈/켠 상태가 반영되지
# 않았다. 실제 적용 중인 값(ActiveStore = 로컬 + GPO 병합 결과)으로 판정한다. W-R16: CDXML cmdlet 시간 제한.

try {
    $profiles = @(Invoke-CimCmdletWithTimeout -Command Get-NetFirewallProfile -Parameters @{ PolicyStore = 'ActiveStore' })
} catch {
    return New-CheckResult -Code "W-64" -Status "ERROR" -Detail "Get-NetFirewallProfile(ActiveStore) 실행 실패: $($_.Exception.Message)"
}
if ($profiles.Count -eq 0) {
    return New-CheckResult -Code "W-64" -Status "ERROR" -Detail "방화벽 프로필 조회 결과가 없음"
}

$disabled = @($profiles | Where-Object { "$($_.Enabled)" -ne "True" })
$evidence = "적용 중인 정책(ActiveStore)`n" + (($profiles | ForEach-Object { "$($_.Name): Enabled=$($_.Enabled)" }) -join "`n")

if ($disabled.Count -eq 0) {
    return New-CheckResult -Code "W-64" -Status "GOOD" -Detail "모든 방화벽 프로필(도메인/개인/공용)이 사용으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-64" -Status "VULN" -Detail ("방화벽이 비활성화된 프로필 존재: " + (($disabled | ForEach-Object { $_.Name }) -join ", ")) -Evidence $evidence
}

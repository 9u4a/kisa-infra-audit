# W-16 (상) 공유 권한 및 사용자 그룹 설정 [fix: confirm]
# 변경: 일반 공유(기본 관리 공유 ADMIN$/C$/IPC$/print$, DC 의 SYSVOL/NETLOGON 제외 - 사용자 숨김 공유 포함)에서 Everyone 공유 권한 제거
# 영향: 공유에서 Everyone 권한 제거 — Everyone 권한으로 그 공유를 쓰던 사용자·프로그램의 접근이 즉시 거부됨
# checks/W-16.ps1: 취약 = 일반(비관리용) 공유에 Everyone 권한이 부여된 경우.
# 해당 공유들에서 Everyone 권한만 제거한다(기본 관리 공유는 W-17 에서 별도 처리).

try {
    $shares = Get-SmbShare -ErrorAction Stop | Where-Object { -not (Test-SmbDefaultShare -Share $_) }   # A7: checks/W-16 과 같은 기준(사용자 숨김 공유 포함)
    # DC 의 SYSVOL/NETLOGON 에서 Everyone 을 빼면 도메인 전체의 그룹 정책·로그온 스크립트 처리가 깨진다 - 절대 건드리지 않는다
    if (Test-IsDomainController) { $shares = $shares | Where-Object { $_.Name -notin @('SYSVOL', 'NETLOGON') } }
} catch {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "Get-SmbShare 실행 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($s in $shares) {
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    $everyone = $access | Where-Object { $_.AccountName -match "Everyone" }
    if (-not $everyone) { continue }
    Revoke-FixShareEveryone -ShareName $s.Name
    if ($Global:FixStatus -eq "APPLIED") { $applied += $s.Name }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "Everyone 권한을 제거한 공유: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "Everyone 권한이 있는 일반 공유가 없음(이미 정상)"
}

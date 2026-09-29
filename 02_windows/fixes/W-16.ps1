# W-16 (상) 공유 권한 및 사용자 그룹 설정 [fix: confirm]
# checks/W-16.ps1: 취약 = 일반(비관리용) 공유에 Everyone 권한이 부여된 경우.
# 해당 공유들에서 Everyone 권한만 제거한다($ 로 끝나는 관리용 공유는 W-17 에서 별도 처리).

try {
    $shares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' }
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

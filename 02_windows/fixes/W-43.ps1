# W-43 (중) 이벤트 로그 파일 접근 통제 설정 [fix: auto]
# checks/W-43.ps1 과 동일한 대상 경로에서 Everyone 허용 ACE 만 제거한다.

$paths = @(
    (Join-Path $env:SystemRoot "System32\winevt\Logs"),
    (Join-Path $env:SystemRoot "System32\config")
) | Where-Object { Test-Path $_ }

if ($paths.Count -eq 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "로그 디렉터리를 찾을 수 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($p in $paths) {
    Remove-FixAclIdentity -Path $p -IdentityPatterns @("Everyone")
    if ($Global:FixStatus -eq "APPLIED") { $applied += $p }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "로그 디렉터리에서 Everyone 권한 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "Everyone 권한이 있는 로그 디렉터리가 없음(이미 정상)"
}

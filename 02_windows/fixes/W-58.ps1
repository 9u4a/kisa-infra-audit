# W-58 (중) 사용자별 홈 디렉터리 권한 설정 [fix: auto]
# checks/W-58.ps1 과 동일한 대상(Public/Default/Default User/All Users 제외)에서
# Everyone 허용 ACE 만 제거한다.

$usersRoot = Join-Path $env:SystemDrive "Users"
if (-not (Test-Path $usersRoot)) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "$usersRoot 디렉터리를 찾을 수 없음"; $Global:FixEvidence = ""
    return
}

$exclude = @("Public", "Default", "Default User", "All Users")
$dirs = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $exclude -notcontains $_.Name }

$applied = @()
foreach ($d in $dirs) {
    $acl = Get-Acl -Path $d.FullName
    $everyone = $acl.Access | Where-Object { $_.IdentityReference -match "Everyone" -and $_.AccessControlType -eq "Allow" }
    if (-not $everyone) { continue }
    Remove-FixAclIdentity -Path $d.FullName -IdentityPatterns @("Everyone")
    if ($Global:FixStatus -eq "APPLIED") { $applied += $d.Name }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "홈 디렉터리에서 Everyone 권한 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "Everyone 권한이 있는 홈 디렉터리가 없음(이미 정상)"
}

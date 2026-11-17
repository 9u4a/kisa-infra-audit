# W-03 (상) 불필요한 계정 제거 [fix: param]
# 값: accounts=비활성화할 로컬 계정 이름(쉼표 구분) - 진단 증적의 활성 로컬 계정 중 운영자가 불필요하다고 판단한 것
# 변경: 지정 로컬 계정 비활성화(Disable-LocalUser) - 삭제하지 않음(프로필·파일·권한 보존)
# 영향: 지정 계정 로그온 즉시 차단 — 그 계정으로 실행하던 서비스·예약 작업·원격 접속이 실패할 수 있음
# 가이드 조치 방법: 불필요한 계정 삭제(또는 비활성화). "불필요" 판단은 사람이 한다(진단은 MANUAL) - 정책 파일 [host:이름] 구역의
# W-03.accounts 값으로 받는다(1.7.0 값 지정 조치). 값은 모두 먼저 검증하고 하나라도 틀리면 아무것도 바꾸지 않는다:
# 없는 계정·이미 비활성·지금 실행 중인 계정·중복, 그리고 비활성화 뒤 활성 로컬 관리자 계정이 하나도 남지 않게 되는 경우(F3).

$accts = @(Get-FixParam -Key "accounts")
if ($accts.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-03.accounts 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}
$me = "$env:USERNAME"
foreach ($a in $accts) {
    if ($seen.ContainsKey($a.ToLowerInvariant())) { $errs += "${a}: 값에 두 번 나옴"; continue }
    $seen[$a.ToLowerInvariant()] = $true
    $u = Get-LocalUser -Name $a -ErrorAction SilentlyContinue
    if (-not $u) { $errs += "${a}: 로컬 계정이 아님(없음)"; continue }
    if (-not $u.Enabled) { $errs += "${a}: 이미 비활성"; continue }
    if ($a -ieq $me) { $errs += "${a}: 지금 조치를 실행한 계정" }
}
try {
    # 로컬 사용자만 남는다(도메인 계정·그룹은 Get-LocalUser -SID 가 찾지 못함) - ObjectClass 는 OS 언어에 따라 달라 쓰지 않는다
    $admins = @(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-544')
    $left = @($admins | ForEach-Object { Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue } |
            Where-Object { $_ -and $_.Enabled -and -not $seen.ContainsKey($_.Name.ToLowerInvariant()) })
    if ($left.Count -eq 0) { $errs += "비활성화하면 활성 로컬 관리자 계정이 하나도 남지 않음" }
} catch { $errs += "Administrators 그룹 구성원 확인 실패: $($_.Exception.Message)" }
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$done = @(); $failed = @()
foreach ($a in $accts) {
    Set-FixLocalAccountDisabled -Name $a -Disabled $true
    if ($Global:FixStatus -eq "APPLIED" -and -not (Get-LocalUser -Name $a).Enabled) { $done += $a } else { $failed += $a }
}
$Global:FixEvidence = (Get-LocalUser | Where-Object { $accts -contains $_.Name } | ForEach-Object { "$($_.Name) Enabled=$($_.Enabled)" }) -join "`n"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "계정 비활성화 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 로컬 계정을 비활성화함: $($done -join ', ')"
}

# W-14 (중) 원격터미널 접속 가능한 사용자 그룹 제한 [fix: param]
# 값: members=Remote Desktop Users 에 등록할 원격 접속용 로컬 계정 이름(쉼표 구분) - 관리자 그룹이 아닌, 미리 만들어 둔 별도 계정
# 변경: 지정 계정을 Remote Desktop Users(S-1-5-32-555) 그룹에 추가 - 계정은 만들지 않음(원복 시 이 조치가 추가한 구성원만 제거)
# 가이드 조치 방법: 관리자 계정 외 원격 접속용 별도 계정을 만들어 원격 데스크톱 사용자 그룹에 등록. 계정 이름·비밀번호를 스크립트가
# 지어낼 수 없어 manual 이었다(W-24·U-28 과 같은 구조) - 1.7.0 값 지정 조치로 운영자가 만든 계정 이름을 정책 값으로 받는다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 있는 로컬 계정·활성·Administrators 구성원이 아님·중복 없음.

$names = @(Get-FixParam -Key "members")
if ($names.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-14.members 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}
try { $adminSids = @(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-544' | ForEach-Object { "$($_.SID)" }) }
catch { $Global:FixStatus = "ERROR"; $Global:FixDetail = "Administrators 그룹 구성원 확인 실패 - 바꾸지 않음: $($_.Exception.Message)"; $Global:FixEvidence = ""; return }
foreach ($n in $names) {
    if ($seen.ContainsKey($n.ToLowerInvariant())) { $errs += "${n}: 값에 두 번 나옴"; continue }
    $seen[$n.ToLowerInvariant()] = $true
    $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
    if (-not $u) { $errs += "${n}: 로컬 계정이 아님(없음) - 계정은 미리 만들어야 함"; continue }
    if (-not $u.Enabled) { $errs += "${n}: 비활성 계정" }
    if ($adminSids -contains $u.SID.Value) { $errs += "${n}: Administrators 구성원 - 관리자 외 별도 계정이어야 함(가이드)" }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$added = @(); $failed = @()
foreach ($n in $names) {
    try { if (Add-FixLocalGroupMemberBySid -GroupSid 'S-1-5-32-555' -Member $n) { $added += $n } }
    catch {
        if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
        $failed += "${n}($($_.Exception.Message))"
    }
}
$Global:FixEvidence = (@(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-555') | ForEach-Object { "$($_.Name) $($_.SID)" }) -join "`n"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "Remote Desktop Users 등록 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "Remote Desktop Users 에 등록함: $(if ($added) { $added -join ', ' } else { '(이미 모두 구성원)' })"
}

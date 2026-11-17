# W-14 (중) 원격터미널 접속 가능한 사용자 그룹 제한
# 판단 기준(가이드 원문): 양호 = 관리자 계정 외 별도 계정을 생성해 원격 접속 사용자 그룹에 등록,
#                        불필요한 계정 없음 / 취약 = 별도 계정이 존재하지 않는 경우
# W-R9: 그룹은 SID(S-1-5-32-555 Remote Desktop Users)로 조회한다 - 예전에는 영문 그룹 이름으로 불러 비영문 OS 에서
# 실패했고, 그 실패와 고아 SID 오류까지 "RDP 미사용 = NA" 로 숨겼다. 그룹 자체가 없는 경우(Windows Home 등
# 원격 데스크톱 호스트 미지원 에디션)만 NA, 조회 실패는 ERROR.

$rdpSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-555')
try {
    $null = $rdpSid.Translate([System.Security.Principal.NTAccount])
} catch [System.Security.Principal.IdentityNotMappedException] {
    return New-CheckResult -Code "W-14" -Status "NA" -Detail "Remote Desktop Users 그룹(S-1-5-32-555)이 이 시스템에 없음 (원격 데스크톱 호스트 미지원 에디션)"
} catch {
    return New-CheckResult -Code "W-14" -Status "ERROR" -Detail "Remote Desktop Users 그룹 확인 실패: $($_.Exception.Message)"
}

try {
    # F-W14(1.4.0): @() 로 감싼다 - 구성원이 1명이면 단일 PSCustomObject 가 되어 Windows PowerShell 5.1 에서 .Count 가 $null
    # (W-14 는 1명 등록돼 있어도 VULN 이었다, 양방향 케이스로 확인)
    $members = @(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-555')
} catch {
    return New-CheckResult -Code "W-14" -Status "ERROR" -Detail "Remote Desktop Users 그룹 구성원 조회 실패: $($_.Exception.Message)"
}

$evidence = ($members | ForEach-Object { "$($_.Name) ($($_.ObjectClass)) $($_.SID)" }) -join "`n"

if ($members.Count -gt 0) {
    return New-CheckResult -Code "W-14" -Status "GOOD" -Detail "Remote Desktop Users 그룹에 원격 접속용 별도 계정이 등록되어 있음 ($($members.Count)명) — 각 계정 필요성은 수동 재확인 권장" -Evidence $evidence
} else {
    # 1.7.0 값 지정 조치: W-14.members 후보(활성 로컬 계정 중 Administrators 가 아닌 것) - lib/policy_draft.py 가 읽는다. 조회 실패는 후보 없음.
    $ev = "구성원 없음"
    try {
        $adminSids = @(Get-LocalGroupMembersBySid -Sid 'S-1-5-32-544' | ForEach-Object { "$($_.SID)" })
        $cand = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and $adminSids -notcontains $_.SID.Value -and $_.Name -notmatch ',' } | ForEach-Object { $_.Name })
        if ($cand.Count -gt 0) { $ev += "`n`n[candidates] $($cand -join ',')" }
    } catch { $ev += " (원격 접속용 후보 계정 조회 실패: $($_.Exception.Message))" }
    return New-CheckResult -Code "W-14" -Status "VULN" -Detail "Remote Desktop Users 그룹에 등록된 별도 계정이 없음 (관리자 계정 외 원격 접속 계정 미구성)" -Evidence $ev
}

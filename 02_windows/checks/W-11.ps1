# W-11 (중) 로컬 로그온 허용
# 판단 기준(가이드 원문): 양호 = 로컬 로그온 허용 정책에 Administrators, IUSR_ 만 존재
#                        취약 = 그 외 계정/그룹이 존재하는 경우
# W-R15: 이름("Administrators$") 대신 SID 로 비교한다(비영문 OS 에서 그룹 이름이 번역됨).
#   S-1-5-32-544 = Administrators, S-1-5-17 = IUSR(IIS 7+ 익명 계정). IIS 6 이하의 로컬 계정 IUSR_<컴퓨터명>은
#   SID 가 컴퓨터마다 달라 이름으로만 허용한다.

$sids = Get-SecPrivilegeSids -Right "SeInteractiveLogonRight"
if ($sids.Count -eq 0) {
    return New-CheckResult -Code "W-11" -Status "MANUAL" -Detail "SeInteractiveLogonRight 조회 결과가 없음 — secedit 값 확인 필요"
}

$extra = @()
$evidenceLines = @()
foreach ($s in $sids) {
    $name = ConvertFrom-Sid $s
    $evidenceLines += "$name ($s)"
    if ($s -eq 'S-1-5-32-544' -or $s -eq 'S-1-5-17') { continue }
    if ($name -match '(^|\\)IUSR_') { continue }
    $extra += $name
}
$evidence = $evidenceLines -join "`n"

if ($extra.Count -eq 0) {
    return New-CheckResult -Code "W-11" -Status "GOOD" -Detail "로컬 로그온 허용 정책에 Administrators/IUSR_ 외 계정이 없음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-11" -Status "VULN" -Detail ("로컬 로그온 허용 정책에 불필요한 계정/그룹 존재: " + ($extra -join ", ")) -Evidence $evidence
}

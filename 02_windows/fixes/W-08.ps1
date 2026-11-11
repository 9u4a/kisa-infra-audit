# W-08 (중) 계정 잠금 기간 설정 [fix: auto]
# 변경: 보안 정책 LockoutDuration=60, ResetLockoutCount=60 (분)
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-08.ps1: 양호 = LockoutDuration/ResetLockoutCount 모두 60분 이상
# G-07: 잠금 임계값(LockoutBadCount)이 0 이면 Windows 가 잠금 기간을 저장하지 않아 적용 후에도 VULN 이었고, 이미 바꾼 보안 정책을
# 항목 단위로 되돌릴 수 없어 FAILED_NOT_ROLLED_BACK 이 남았다(한글 Server 2022 실측). 임계값은 W-04 의 조치(업무 영향 판단 필요)라
# 여기서 대신 켜지 않고, 아무것도 바꾸지 않은 채 "W-04 먼저"로 끝낸다. 같은 실행에서 W-04 가 승인되면 코드 순서상 먼저 적용된다.

Clear-SecEditCache
$bad = Get-SecPolicyValue -Section "System Access" -Name "LockoutBadCount"
if ($null -ne $bad -and [int]$bad -eq 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "계정 잠금 임계값이 0(잠금 사용 안 함)이라 잠금 기간을 설정할 수 없음 - W-04(계정 잠금 임계값)를 먼저 조치한 뒤 다시 실행(변경 없음)"
    $Global:FixEvidence = "LockoutBadCount=$bad"
    return
}
Set-FixSecPolicyValue -Section "System Access" -Values @{ LockoutDuration = 60; ResetLockoutCount = 60 }

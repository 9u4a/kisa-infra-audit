# W-11 (중) 로컬 로그온 허용 [fix: confirm]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-11.ps1: 양호 = SeInteractiveLogonRight 에 Administrators/IUSR_ 외 계정 없음.
# 가이드가 명시한 허용 대상(Administrators, IUSR_)만으로 값을 재설정한다.

$sids = @("*S-1-5-32-544")  # BUILTIN\Administrators (well-known SID)
if (Get-LocalUser -Name "IUSR" -ErrorAction SilentlyContinue) {
    $sids += "*S-1-5-17"    # NT AUTHORITY\IUSR (well-known SID)
}

Set-FixSecPrivilege -Right "SeInteractiveLogonRight" -Sids $sids

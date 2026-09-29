# W-11 (중) 로컬 로그온 허용 [fix: confirm]
# checks/W-11.ps1: 양호 = SeInteractiveLogonRight 에 Administrators/IUSR_ 외 계정 없음.
# 가이드가 명시한 허용 대상(Administrators, IUSR_)만으로 값을 재설정한다.

$sids = @("*S-1-5-32-544")  # BUILTIN\Administrators (well-known SID)
if (Get-LocalUser -Name "IUSR" -ErrorAction SilentlyContinue) {
    $sids += "*S-1-5-17"    # NT AUTHORITY\IUSR (well-known SID)
}

Set-FixSecPrivilege -Right "SeInteractiveLogonRight" -Sids $sids

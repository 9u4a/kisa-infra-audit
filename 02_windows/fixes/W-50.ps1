# W-50 (상) 보안 감사를 로그 할 수 없는 경우 즉시 시스템 종료 [fix: auto]
# 변경: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\CrashOnAuditFail = 0 (DWORD)

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "CrashOnAuditFail" -Value 0 -Type DWord

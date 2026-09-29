# W-04 (상) 계정 잠금 임계값 설정 [fix: confirm]
# checks/W-04.ps1: 양호 = LockoutBadCount 1~5. 가이드 권고값(5회)으로 설정한다.

Set-FixSecPolicyValue -Section "System Access" -Values @{ LockoutBadCount = 5 }

# W-08 (중) 계정 잠금 기간 설정 [fix: auto]
# checks/W-08.ps1: 양호 = LockoutDuration/ResetLockoutCount 모두 60분 이상

Set-FixSecPolicyValue -Section "System Access" -Values @{ LockoutDuration = 60; ResetLockoutCount = 60 }

# W-08 (중) 계정 잠금 기간 설정 [fix: auto]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-08.ps1: 양호 = LockoutDuration/ResetLockoutCount 모두 60분 이상

Set-FixSecPolicyValue -Section "System Access" -Values @{ LockoutDuration = 60; ResetLockoutCount = 60 }

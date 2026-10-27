# W-04 (상) 계정 잠금 임계값 설정 [fix: confirm]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-04.ps1: 양호 = LockoutBadCount 1~5. 가이드 권고값(5회)으로 설정한다.

Set-FixSecPolicyValue -Section "System Access" -Values @{ LockoutBadCount = 5 }

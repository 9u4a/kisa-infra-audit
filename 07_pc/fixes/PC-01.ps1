# PC-01 (상) 비밀번호의 주기적 변경 [fix: confirm]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/PC-01.ps1: 양호 = MaximumPasswordAge 1~90일

Set-FixSecPolicyValue -Section "System Access" -Values @{ MaximumPasswordAge = 90 }

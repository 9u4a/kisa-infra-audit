# W-05 (상) 해독 가능한 암호화를 사용하여 암호 저장 해제 [fix: auto]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-05.ps1: 양호 = ClearTextPassword=0

Set-FixSecPolicyValue -Section "System Access" -Values @{ ClearTextPassword = 0 }

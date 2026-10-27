# PC-02 (상) 비밀번호 관리정책 설정 [fix: auto]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/PC-02.ps1: 양호 = PasswordComplexity=1 및 MinimumPasswordLength>=8

Set-FixSecPolicyValue -Section "System Access" -Values @{ PasswordComplexity = 1; MinimumPasswordLength = 8 }

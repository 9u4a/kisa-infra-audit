# W-12 (중) 익명 SID/이름 변환 허용 해제 [fix: confirm]
# 변경: 보안 정책 LSAAnonymousNameLookup=0 ("네트워크 액세스: 익명 SID/이름 변환 허용" 사용 안 함)
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-12.ps1: 양호 = secedit [System Access] LSAAnonymousNameLookup=0.
# 1.7.0: 예전에는 "LSA 정책 객체라 secedit 로 바꿀 수 없다"며 manual 이었으나 틀린 판단이었다 - 이 값은 secedit /configure 의
# [System Access] 로 적용되고, 양방향 케이스(tests/fixtures/cases/W-12.ps1)가 같은 방법으로 취약 상태를 만든다.

Set-FixSecPolicyValue -Section "System Access" -Values @{ LSAAnonymousNameLookup = 0 }

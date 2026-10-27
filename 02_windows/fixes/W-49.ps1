# W-49 (상) 원격 시스템에서 강제로 시스템 종료 [fix: auto]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-49.ps1: 양호 = SeRemoteShutdownPrivilege 에 Administrators 만 존재.

Set-FixSecPrivilege -Right "SeRemoteShutdownPrivilege" -Sids @("*S-1-5-32-544")

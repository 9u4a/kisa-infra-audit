# W-49 (상) 원격 시스템에서 강제로 시스템 종료 [fix: auto]
# checks/W-49.ps1: 양호 = SeRemoteShutdownPrivilege 에 Administrators 만 존재.

Set-FixSecPrivilege -Right "SeRemoteShutdownPrivilege" -Sids @("*S-1-5-32-544")

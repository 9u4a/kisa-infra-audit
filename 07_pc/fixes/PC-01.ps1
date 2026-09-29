# PC-01 (상) 비밀번호의 주기적 변경 [fix: confirm]
# checks/PC-01.ps1: 양호 = MaximumPasswordAge 1~90일

Set-FixSecPolicyValue -Section "System Access" -Values @{ MaximumPasswordAge = 90 }

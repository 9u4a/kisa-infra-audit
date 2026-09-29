# W-05 (상) 해독 가능한 암호화를 사용하여 암호 저장 해제 [fix: auto]
# checks/W-05.ps1: 양호 = ClearTextPassword=0

Set-FixSecPolicyValue -Section "System Access" -Values @{ ClearTextPassword = 0 }

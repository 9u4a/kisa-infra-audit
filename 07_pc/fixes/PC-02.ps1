# PC-02 (상) 비밀번호 관리정책 설정 [fix: auto]
# checks/PC-02.ps1: 양호 = PasswordComplexity=1 및 MinimumPasswordLength>=8

Set-FixSecPolicyValue -Section "System Access" -Values @{ PasswordComplexity = 1; MinimumPasswordLength = 8 }

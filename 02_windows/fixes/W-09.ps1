# W-09 (상) 비밀번호 관리 정책 설정 [fix: auto]
# checks/W-09.ps1: 양호 = 복잡성 사용, 최소 길이 8자 이상, 최대 사용기간 1~90일, 최소 사용기간
# 1일 이상, 암호 기억 개수 4개 이상. 가이드 권고값으로 일괄 설정한다.

Set-FixSecPolicyValue -Section "System Access" -Values @{
    PasswordComplexity   = 1
    MinimumPasswordLength = 8
    MaximumPasswordAge   = 90
    MinimumPasswordAge   = 1
    PasswordHistorySize  = 4
}

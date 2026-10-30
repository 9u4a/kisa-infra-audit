# W-09 케이스. 가이드: 양호 = 비밀번호 관리 정책(복잡성, 최소 길이 8, 최대 사용 기간 90일 이하, 최소 사용 기간 1일 이상,
# 최근 암호 기억 4개 이상)이 모두 적용 / 취약 = 모두 적용되어 있지 않은 경우(하나라도 빠지면 취약)
@{
    States = [ordered]@{
        'complexity-off' = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 0; MinimumPasswordLength = 8; MaximumPasswordAge = 90; MinimumPasswordAge = 1; PasswordHistorySize = 4 } } }
        'history-2'      = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 1; MinimumPasswordLength = 8; MaximumPasswordAge = 90; MinimumPasswordAge = 1; PasswordHistorySize = 2 } } }
        'all-set'        = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 1; MinimumPasswordLength = 8; MaximumPasswordAge = 90; MinimumPasswordAge = 1; PasswordHistorySize = 4 } } }
    }
    Fix    = @{ From = 'history-2' }
}

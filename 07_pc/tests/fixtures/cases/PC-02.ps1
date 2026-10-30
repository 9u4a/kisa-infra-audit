# PC-02 케이스. 가이드: 양호 = 복잡성을 만족하는 비밀번호 정책 / 취약 = 비밀번호 미사용 또는 추측하기 쉬운 짧은 비밀번호 허용
# (check: 복잡성 사용 + 최소 길이 8 이상). Chain: X-02 회귀 - 같은 프로세스에서 PC-01 → PC-02 보안 정책 조치 연속 적용·재검증.
@{
    States = [ordered]@{
        'weak'       = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 0; MinimumPasswordLength = 0; MaximumPasswordAge = -1 } } }
        'short'      = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 1; MinimumPasswordLength = 6 } } }
        'complex-8'  = @{ Sec = @{ 'System Access' = @{ PasswordComplexity = 1; MinimumPasswordLength = 8 } } }
    }
    Fix    = @{ From = 'weak' }
    Chain  = @{ From = 'weak'; Codes = @('PC-01', 'PC-02') }
}
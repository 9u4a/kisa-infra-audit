# W-08 케이스. 가이드: 양호 = 계정 잠금 기간·원래대로 설정 기간 모두 60분 이상 / 취약 = 미설정 또는 60분 미만.
# 잠금 임계값 0 = 잠금 기간 미설정(취약, W-R8), 잠금 기간 -1 = 관리자가 해제할 때까지(60분 이상과 같음, W-R8).
# Chain: X-02 회귀 - 같은 프로세스에서 W-04 → W-08 보안 정책 조치를 연달아 적용하고 같은 프로세스에서 재검증한다.
@{
    States = [ordered]@{
        'duration-30'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 10; LockoutDuration = 30; ResetLockoutCount = 30 } } }
        'lockout-off'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 0 } } }
        'duration-60'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 10; LockoutDuration = 60; ResetLockoutCount = 60 } } }
        'admin-unlock' = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 10; LockoutDuration = -1; ResetLockoutCount = 60 } } }
    }
    Fix    = @{ From = 'duration-30' }
    Chain  = @{ From = 'duration-30'; Codes = @('W-04', 'W-08') }
}

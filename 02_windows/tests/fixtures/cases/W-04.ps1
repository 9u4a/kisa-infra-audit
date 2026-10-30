# W-04 케이스. 가이드: 양호 = 계정 잠금 임계값 5 이하 / 취약 = 5 초과(0 = 미설정도 취약 - check 주석)
@{
    States = [ordered]@{
        'threshold-10' = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 10 } } }
        'threshold-0'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 0 } } }
        'threshold-5'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 5 } } }
        'threshold-3'  = @{ Sec = @{ 'System Access' = @{ LockoutBadCount = 3 } } }
    }
    Fix    = @{ From = 'threshold-10' }
}

# W-05 케이스. 가이드: 양호 = "해독 가능한 암호화를 사용하여 암호 저장" 사용 안 함 / 취약 = 사용
@{
    States = [ordered]@{
        'reversible-on'  = @{ Sec = @{ 'System Access' = @{ ClearTextPassword = 1 } } }
        'reversible-off' = @{ Sec = @{ 'System Access' = @{ ClearTextPassword = 0 } } }
    }
    Fix    = @{ From = 'reversible-on' }
}

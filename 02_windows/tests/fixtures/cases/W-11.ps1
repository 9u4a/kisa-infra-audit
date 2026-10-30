# W-11 케이스. 가이드: 양호 = 로컬 로그온 허용에 Administrators, IUSR_ 만 / 취약 = 그 외 계정·그룹 존재
@{
    States = [ordered]@{
        'users-allowed' = @{ Sec = @{ 'Privilege Rights' = @{ SeInteractiveLogonRight = '*S-1-5-32-544,*S-1-5-32-545' } } }
        'admins-only'   = @{ Sec = @{ 'Privilege Rights' = @{ SeInteractiveLogonRight = '*S-1-5-32-544' } } }
        'admins-iusr'   = @{ Sec = @{ 'Privilege Rights' = @{ SeInteractiveLogonRight = '*S-1-5-32-544,*S-1-5-17' } } }
    }
    Fix    = @{ From = 'users-allowed' }
}

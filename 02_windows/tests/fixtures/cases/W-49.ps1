# W-49 케이스. 가이드: 양호 = "원격 시스템에서 강제로 시스템 종료"에 Administrators 만 / 취약 = 그 외 계정·그룹 존재
@{
    States = [ordered]@{
        'admins-users' = @{ Sec = @{ 'Privilege Rights' = @{ SeRemoteShutdownPrivilege = '*S-1-5-32-544,*S-1-5-32-545' } } }
        'admins-only'  = @{ Sec = @{ 'Privilege Rights' = @{ SeRemoteShutdownPrivilege = '*S-1-5-32-544' } } }
    }
    Fix    = @{ From = 'admins-users' }
}
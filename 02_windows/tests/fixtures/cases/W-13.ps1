# W-13 케이스. 가이드: 양호 = "콘솔 로그온 시 로컬 계정에서 빈 암호 사용 제한" 사용 / 취약 = 사용 안 함
@{
    States = [ordered]@{
        'blank-allowed'    = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'LimitBlankPasswordUse'; V = 0 }) }
        'blank-restricted' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'LimitBlankPasswordUse'; V = 1 }) }
    }
    Fix    = @{ From = 'blank-allowed' }
}

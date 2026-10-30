# W-51 케이스. 가이드: 양호 = "SAM 계정과 공유의 익명 열거 허용 안 함" 사용 / 취약 = 사용 안 함(RestrictAnonymous·RestrictAnonymousSAM)
@{
    States = [ordered]@{
        'shares-enumerable' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymous'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymousSAM'; V = 1 }) }
        'sam-enumerable'    = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymous'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymousSAM'; V = 0 }) }
        'both-restricted'   = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymous'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymousSAM'; V = 1 }) }
    }
    Fix    = @{ From = 'shares-enumerable' }
}
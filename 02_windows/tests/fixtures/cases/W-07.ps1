# W-07 케이스. 가이드: 양호 = "Everyone 사용 권한을 익명 사용자에게 적용" 사용 안 함 / 취약 = 사용.
# 값이 없을 때 기본값은 사용 안 함(0) - Microsoft "Network access: Let Everyone permissions apply to anonymous users"(기본 Disabled)
@{
    States = [ordered]@{
        'enabled'  = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'EveryoneIncludesAnonymous'; V = 1 }) }
        'disabled' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'EveryoneIncludesAnonymous'; V = 0 }) }
        'unset'    = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'EveryoneIncludesAnonymous'; V = $null }) }
    }
    Fix    = @{ From = 'enabled' }
}

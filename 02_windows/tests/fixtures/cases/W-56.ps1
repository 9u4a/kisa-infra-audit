# W-56 케이스. 가이드: 양호 = "로그온 시간 만료 시 연결 끊기" 사용 + 유휴 시간 15분 이하 / 취약 = 사용 안 함 또는 15분 초과
@{
    States = [ordered]@{
        'no-forced-logoff' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'enableforcedlogoff'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'autodisconnect'; V = 15 }) }
        'idle-30'          = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'enableforcedlogoff'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'autodisconnect'; V = 30 }) }
        'forced-idle-15'   = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'enableforcedlogoff'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'autodisconnect'; V = 15 }) }
    }
    Fix    = @{ From = 'no-forced-logoff' }
}
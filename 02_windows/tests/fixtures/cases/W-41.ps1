# W-41 케이스. 가이드: 양호 = NTP 및 시각 동기화 설정 / 취약 = 미설정(시간 서비스 중지, 동기화 유형 NoSync)
@{
    States = [ordered]@{
        'w32time-disabled' = @{ Svc = @{ W32Time = 'Disabled' } }
        'nosync'           = @{ Svc = @{ W32Time = 'Running' }; Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'; N = 'Type'; V = 'NoSync'; T = 'String' }) }
        'ntp-configured'   = @{ Svc = @{ W32Time = 'Running' }; Reg = @(
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'; N = 'Type'; V = 'NTP'; T = 'String' },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'; N = 'NtpServer'; V = 'time.windows.com,0x9'; T = 'String' }) }
    }
    Fix    = @{ From = 'w32time-disabled' }
}

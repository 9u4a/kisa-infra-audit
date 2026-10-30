# W-36 케이스. 가이드: 양호 = 원격 제어 Timeout 30분 이하 / 취약 = 미적용 또는 30분 초과(RDP 미사용은 해당 기능 없음 = 양호)
@{
    States = [ordered]@{
        'rdp-no-timeout' = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MaxIdleTime'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MaxIdleTime'; V = 0 }) }
        'rdp-60min'      = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MaxIdleTime'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MaxIdleTime'; V = 3600000 }) }
        'rdp-30min'      = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MaxIdleTime'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MaxIdleTime'; V = 1800000 }) }
        'gpo-15min'      = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MaxIdleTime'; V = 900000 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MaxIdleTime'; V = 0 }) }
        'rdp-disabled'   = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 1 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MaxIdleTime'; V = 0 }) }
    }
    Fix    = @{ From = 'rdp-no-timeout' }
}

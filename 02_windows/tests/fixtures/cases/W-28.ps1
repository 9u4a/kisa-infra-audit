# W-28 케이스. 가이드: 양호 = RDP 미사용 또는 암호화 수준 "클라이언트 호환 가능(중간)" 이상 / 취약 = 사용 중이며 "낮음".
# 그룹 정책(Policies\...\Terminal Services) 값이 로컬 값보다 우선한다(W-R10).
@{
    States = [ordered]@{
        'rdp-low'      = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MinEncryptionLevel'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MinEncryptionLevel'; V = 1 }) }
        'rdp-client'   = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MinEncryptionLevel'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MinEncryptionLevel'; V = 2 }) }
        'rdp-disabled' = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 1 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MinEncryptionLevel'; V = 1 }) }
        'gpo-low'      = @{ Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fDenyTSConnections'; V = $null },
                @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'MinEncryptionLevel'; V = 1 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 0 },
                @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; N = 'MinEncryptionLevel'; V = 3 }) }
    }
    Fix    = @{ From = 'rdp-low' }
}

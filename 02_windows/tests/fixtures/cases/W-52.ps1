# W-52 케이스. 가이드: 양호 = AutoAdminLogon 값이 없거나 0 / 취약 = 1. (자동 로그온 비밀번호 DefaultPassword 는 케이스 동안 비워 두고 원복)
@{
    States = [ordered]@{
        'autologon-on'  = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = '1'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
        'autologon-off' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = '0'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
        'unset'         = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = $null }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
    }
    Fix    = @{ From = 'autologon-on' }
}
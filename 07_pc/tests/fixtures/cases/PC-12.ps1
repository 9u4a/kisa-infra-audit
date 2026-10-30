# PC-12 케이스. 가이드: 양호 = Windows 자동 로그인 비활성화 / 취약 = 활성화(AutoAdminLogon=1). DefaultPassword 는 케이스 동안 비워 두고 원복
@{
    States = [ordered]@{
        'autologon-on'  = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = '1'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
        'autologon-off' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = '0'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
        'unset'         = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = $null }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'DefaultPassword'; V = $null }) }
    }
    Fix    = @{ From = 'autologon-on' }
}
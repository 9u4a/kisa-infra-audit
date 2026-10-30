# PC-03 케이스. 가이드: 양호 = 복구 콘솔 자동 로그온 허용 사용 안 함(값이 없으면 사용 안 함 - 가이드 원문) / 취약 = 사용
@{
    States = [ordered]@{
        'autologon-allowed' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole'; N = 'SecurityLevel'; V = 1 }) }
        'disabled'          = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole'; N = 'SecurityLevel'; V = 0 }) }
        'unset'             = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole'; N = 'SecurityLevel'; V = $null }) }
    }
    Fix    = @{ From = 'autologon-allowed' }
}
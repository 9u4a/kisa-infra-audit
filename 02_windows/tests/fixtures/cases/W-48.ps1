# W-48 케이스. 가이드: 양호 = "로그온하지 않고 시스템 종료 허용" 사용 안 함 / 취약 = 사용. 값이 없으면 Windows 기본값 사용(=취약, 02_windows/CLAUDE.md)
@{
    States = [ordered]@{
        'allowed'    = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'ShutdownWithoutLogon'; V = 1 }) }
        'unset'      = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'ShutdownWithoutLogon'; V = $null }) }
        'disallowed' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'ShutdownWithoutLogon'; V = 0 }) }
    }
    Fix    = @{ From = 'allowed' }
}
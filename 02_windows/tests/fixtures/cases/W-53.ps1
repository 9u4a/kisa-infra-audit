# W-53 케이스. 가이드: 양호 = "이동식 미디어 포맷 및 꺼내기 허용"이 Administrators / 취약 = 아님(AllocateDASD 1·2)
@{
    States = [ordered]@{
        'interactive-users' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AllocateDASD'; V = '2'; T = 'String' }) }
        'admins'            = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AllocateDASD'; V = '0'; T = 'String' }) }
    }
    Fix    = @{ From = 'interactive-users' }
}
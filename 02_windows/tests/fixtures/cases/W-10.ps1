# W-10 케이스. 가이드: 양호 = "마지막 사용자 이름 표시 안 함" 사용 / 취약 = 사용 안 함
@{
    States = [ordered]@{
        'show-last-user' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'DontDisplayLastUserName'; V = 0 }) }
        'hide-last-user' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'DontDisplayLastUserName'; V = 1 }) }
    }
    Fix    = @{ From = 'show-last-user' }
}

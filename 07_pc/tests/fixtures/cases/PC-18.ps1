# PC-18 케이스. 가이드: 양호 = 원격 지원 사용 안 함 / 취약 = 사용(기본값). 그룹 정책 값이 로컬 값보다 우선(W-R10).
@{
    States = [ordered]@{
        'local-allow' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fAllowToGetHelp'; V = $null }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; N = 'fAllowToGetHelp'; V = 1 }) }
        'local-deny'  = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fAllowToGetHelp'; V = $null }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; N = 'fAllowToGetHelp'; V = 0 }) }
        'gpo-allow'   = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fAllowToGetHelp'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; N = 'fAllowToGetHelp'; V = 0 }) }
        'gpo-deny'    = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; N = 'fAllowToGetHelp'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; N = 'fAllowToGetHelp'; V = 1 }) }
    }
    Fix    = @{ From = 'local-allow' }
}
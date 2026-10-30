# PC-06 케이스. 가이드: 양호 = Windows Messenger 중지 또는 상용 메신저 미설치 / 취약 = 실행 중이거나 상용 메신저 설치(제거 목록 흔적). 조치는 manual(F-R2).
@{
    States = [ordered]@{
        'messenger-installed' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KisaCaseMessenger'; N = 'DisplayName'; V = 'Slack (kisa case)'; T = 'String' }) }
        'no-messenger'        = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KisaCaseMessenger'; N = 'DisplayName'; V = $null }) }
    }
}
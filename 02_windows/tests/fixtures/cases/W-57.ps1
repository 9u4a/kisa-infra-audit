# W-57 케이스. 가이드: 양호 = 로그온 경고 메시지 제목 및 내용 설정 / 취약 = 설정되어 있지 않음
@{
    States = [ordered]@{
        'empty'      = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeCaption'; V = ''; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeText'; V = ''; T = 'String' }) }
        'title-only' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeCaption'; V = 'Notice'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeText'; V = ''; T = 'String' }) }
        'set'        = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeCaption'; V = 'Notice'; T = 'String' }, @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'LegalNoticeText'; V = 'Authorized use only.'; T = 'String' }) }
    }
    Fix    = @{ From = 'empty' }
}
# W-47 케이스. 가이드: 양호 = 화면 보호기 사용 + 대기 10분 이하 + 해제 암호 / 취약 = 미설정·암호 미사용·10분 초과.
# 사용자별(HKCU) 설정이라 실행 계정 기준으로만 확인할 수 있어, 기준 미충족은 실제 로그온 계정 재확인이 필요한 MANUAL(manual-by-design).
@{
    States = [ordered]@{
        'secure-10min' = @{ Reg = @(
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaveActive'; V = '1'; T = 'String' },
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaverIsSecure'; V = '1'; T = 'String' },
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaveTimeOut'; V = '600'; T = 'String' }) }
        'no-password'  = @{ Reg = @(
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaveActive'; V = '1'; T = 'String' },
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaverIsSecure'; V = '0'; T = 'String' },
                @{ P = 'HKCU:\Control Panel\Desktop'; N = 'ScreenSaveTimeOut'; V = '600'; T = 'String' }) }
    }
}

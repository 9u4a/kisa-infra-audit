# PC-01 케이스(형식: 02_windows/tests/case_runner.ps1 머리말). 가이드: 양호 = 최대 암호 사용 기간 90일 이하 / 취약 = 제한 없음 또는 90일 초과
@{
    States = [ordered]@{
        'max-age-unlimited' = @{ Sec = @{ 'System Access' = @{ MaximumPasswordAge = -1 } } }
        'max-age-120'       = @{ Sec = @{ 'System Access' = @{ MaximumPasswordAge = 120 } } }
        'max-age-90'        = @{ Sec = @{ 'System Access' = @{ MaximumPasswordAge = 90 } } }
    }
    Fix    = @{ From = 'max-age-120' }
}
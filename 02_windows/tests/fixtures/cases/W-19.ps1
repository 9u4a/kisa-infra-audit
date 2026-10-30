# W-19 케이스. 가이드: 양호 = IIS 미사용 또는 필요에 의해 사용 / 취약 = 불필요하게 사용.
# "필요 여부"는 업무 판단이라 구동 중이면 MANUAL(manual-by-design), 중지면 GOOD.
@{
    Resources = @(@{ Svc = 'WAS' })
    States    = [ordered]@{
        'iis-stopped' = @{ Svc = @{ W3SVC = 'Stopped' } }
        'iis-running' = @{ Svc = @{ W3SVC = 'Running' } }
    }
}

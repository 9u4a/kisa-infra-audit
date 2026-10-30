# W-44 케이스. 가이드: 양호 = Remote Registry 서비스 중지 / 취약 = 사용 중
@{
    States = [ordered]@{
        'remote-registry-running' = @{ Svc = @{ RemoteRegistry = 'Running' } }
        'remote-registry-stopped' = @{ Svc = @{ RemoteRegistry = 'Stopped' } }
    }
    Fix    = @{ From = 'remote-registry-running' }
}

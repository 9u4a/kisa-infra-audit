# W-18 케이스. 가이드: 양호 = 일반적으로 불필요한 서비스(목록)가 중지 / 취약 = 구동 중
@{
    States = [ordered]@{
        'remote-registry-running' = @{ Svc = @{ RemoteRegistry = 'Running' } }
        'all-stopped'             = @{ Svc = @{ RemoteRegistry = 'Disabled'; SSDPSRV = 'Disabled'; upnphost = 'Disabled'; simptcp = 'Disabled'; Browser = 'Disabled'; WerSvc = 'Disabled' } }
    }
    Fix    = @{ From = 'remote-registry-running' }
}

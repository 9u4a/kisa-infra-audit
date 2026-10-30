# PC-05 케이스. 가이드: 양호 = 일반적으로 불필요한 서비스(목록)가 중지 / 취약 = 중지되지 않음
@{
    States = [ordered]@{
        'remote-registry-running' = @{ Svc = @{ RemoteRegistry = 'Running' } }
        'all-stopped'             = @{ Svc = @{ RemoteRegistry = 'Disabled'; SSDPSRV = 'Disabled'; upnphost = 'Disabled'; WerSvc = 'Disabled'; TapiSrv = 'Disabled'; Fax = 'Disabled' } }
    }
    Fix    = @{ From = 'remote-registry-running' }
}
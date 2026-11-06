# W-18 케이스. 가이드: 양호 = 일반적으로 불필요한 서비스(목록)가 중지 / 취약 = 구동 중
# A8: 실행 중이 아니어도 시작 유형이 사용 안 함이 아니면(트리거 시작) 취약 - 'stopped-manual-start' 가 그 재현
@{
    States = [ordered]@{
        'remote-registry-running' = @{ Svc = @{ RemoteRegistry = 'Running' } }
        'all-stopped'             = @{ Svc = @{ RemoteRegistry = 'Disabled'; SSDPSRV = 'Disabled'; upnphost = 'Disabled'; simptcp = 'Disabled'; Browser = 'Disabled'; WerSvc = 'Disabled' } }
        'stopped-manual-start'    = @{
            Svc   = @{ RemoteRegistry = 'Stopped'; SSDPSRV = 'Disabled'; upnphost = 'Disabled'; simptcp = 'Disabled'; Browser = 'Disabled'; WerSvc = 'Disabled' }
            Set   = { Set-Service -Name RemoteRegistry -StartupType Manual }
            Check = { $s = Get-CaseService -Name RemoteRegistry; if ($s -and $s.StartMode -eq 'Manual') { $true } else { "RemoteRegistry=$($s.State)/$($s.StartMode)" } }
        }
    }
    Fix    = @{ From = 'remote-registry-running' }
}

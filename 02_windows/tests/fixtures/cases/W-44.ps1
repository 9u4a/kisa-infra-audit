# W-44 케이스. 가이드: 양호 = Remote Registry 서비스 중지 / 취약 = 사용 중
# A8: 트리거 시작 서비스라 시작 유형이 수동/자동이면 Stopped 여도 원격 요청 시 켜진다 - 중지 + 사용 안 함만 GOOD
@{
    States = [ordered]@{
        'remote-registry-running' = @{ Svc = @{ RemoteRegistry = 'Running' } }
        'remote-registry-stopped' = @{ Svc = @{ RemoteRegistry = 'Disabled' } }
        'stopped-manual-start'    = @{
            Svc   = @{ RemoteRegistry = 'Stopped' }
            Set   = { Set-Service -Name RemoteRegistry -StartupType Manual }
            Check = { $s = Get-CaseService -Name RemoteRegistry; if ($s -and $s.StartMode -eq 'Manual') { $true } else { "RemoteRegistry=$($s.State)/$($s.StartMode)" } }
        }
    }
    Fix    = @{ From = 'remote-registry-running' }
}

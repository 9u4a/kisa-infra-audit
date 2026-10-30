# W-43 케이스. 가이드: 양호 = 로그 디렉터리 접근 권한에 Everyone 없음 / 취약 = 있음
@{
    Resources = @(@{ Save = { Save-CaseAcl (Join-Path $env:SystemRoot 'System32\winevt\Logs') }; Restore = { param($o) Restore-CaseAcl $o } })
    States    = [ordered]@{
        'logs-everyone'    = @{
            Set   = { Invoke-CaseIcacls @((Join-Path $env:SystemRoot 'System32\winevt\Logs'), '/grant', '*S-1-1-0:(R)') }
            Check = { if (Test-CaseAclHasSid -Path (Join-Path $env:SystemRoot 'System32\winevt\Logs') -Sid 'S-1-1-0') { $true } else { "Everyone ACE 없음" } }
        }
        'logs-no-everyone' = @{
            Check = { $p = @((Join-Path $env:SystemRoot 'System32\winevt\Logs'), (Join-Path $env:SystemRoot 'System32\config')) | Where-Object { Test-CaseAclHasSid -Path $_ -Sid 'S-1-1-0' }; if (@($p).Count -eq 0) { $true } else { "Everyone ACE: $($p -join ',')" } }
        }
    }
    Fix       = @{ From = 'logs-everyone' }
}

# W-22 케이스. 가이드: 양호 = FTP 홈 디렉터리에 Everyone 권한 없음 / 취약 = 있음
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Remove-CaseFtpSites } })
    States    = [ordered]@{
        'home-everyone'    = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { $dir = New-CaseFtpSite; Invoke-CaseIcacls @($dir, '/grant', '*S-1-1-0:(OI)(CI)(RX)') }
            Check = { if (Test-CaseAclHasSid -Path (Join-Path $env:SystemDrive 'kisa_case\kisa_case_ftp') -Sid 'S-1-1-0') { $true } else { "Everyone ACE 없음" } }
        }
        'home-no-everyone' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { New-CaseFtpSite | Out-Null }
            Check = { if (-not (Test-CaseAclHasSid -Path (Join-Path $env:SystemDrive 'kisa_case\kisa_case_ftp') -Sid 'S-1-1-0')) { $true } else { "Everyone ACE 있음" } }
        }
        'ftp-stopped'      = @{ Svc = @{ FTPSVC = 'Stopped' } }
    }
    Fix       = @{ From = 'home-everyone' }
}

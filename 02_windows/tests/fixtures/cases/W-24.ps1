# W-24 케이스. 가이드: 양호 = 특정 IP 에서만 FTP 접속하도록 접근 제어 / 취약 = 접근 제어 미적용. 조치는 manual(허용 IP 를 정할 수 없음)
@{
    Resources = @(@{
            Save    = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; [PSCustomObject]@{ Allow = "$($s.allowUnlisted)" -ne 'False'; Ips = @($s.Collection | ForEach-Object { $_.ipAddress }) } }
            Restore = {
                param($o)
                Remove-CaseFtpSites
                foreach ($ip in @((Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\').Collection | ForEach-Object { $_.ipAddress })) {
                    if (@($o.Ips) -notcontains $ip) { Remove-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name '.' -AtElement @{ ipAddress = $ip } }
                }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $o.Allow
            }
        })
    States    = [ordered]@{
        'no-ip-restriction' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { New-CaseFtpSite | Out-Null; Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $true }
            Check = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; if ("$($s.allowUnlisted)" -ne 'False') { $true } else { "allowUnlisted=$($s.allowUnlisted)" } }
        }
        'ip-restricted'     = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                Add-WebConfiguration -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Value @{ ipAddress = '127.0.0.1'; allowed = 'true' }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $false
            }
            Check = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; if ("$($s.allowUnlisted)" -eq 'False' -and @($s.Collection).Count -gt 0) { $true } else { "allowUnlisted=$($s.allowUnlisted) rules=$(@($s.Collection).Count)" } }
        }
        'ftp-stopped'       = @{ Svc = @{ FTPSVC = 'Stopped' } }
    }
}

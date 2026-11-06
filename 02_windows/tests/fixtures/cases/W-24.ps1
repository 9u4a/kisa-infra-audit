# W-24 케이스. 가이드: 양호 = 특정 IP 에서만 FTP 접속하도록 접근 제어 / 취약 = 접근 제어 미적용. 조치는 manual(허용 IP 를 정할 수 없음)
# A9: 가이드 비고 "마스터 속성과 모든 사이트에 적용" - 마스터만 막고 사이트 <location> 에서 allowUnlisted=true 로 연 상태가 예전 거짓 GOOD
@{
    Resources = @(@{
            Save    = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; [PSCustomObject]@{ Allow = "$($s.allowUnlisted)" -ne 'False'; Ips = @($s.Collection | ForEach-Object { $_.ipAddress }) } }
            Restore = {
                param($o)
                # 사이트 단위 <location path="kisa_case_ftp"> 설정은 사이트를 지워도 applicationHost.config 에 남을 수 있어 먼저 지운다
                Clear-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp' -Filter '/system.ftpServer/security/ipSecurity' -ErrorAction SilentlyContinue
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
        'site-override-open' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                Add-WebConfiguration -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Value @{ ipAddress = '127.0.0.1'; allowed = 'true' }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $false
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $true
            }
            Check = {
                $m = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'
                $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp'
                if ("$($m.allowUnlisted)" -eq 'False' -and "$($s.allowUnlisted)" -eq 'True') { $true } else { "master=$($m.allowUnlisted) site=$($s.allowUnlisted)" }
            }
        }
        'ftp-stopped'       = @{ Svc = @{ FTPSVC = 'Stopped' } }
    }
}

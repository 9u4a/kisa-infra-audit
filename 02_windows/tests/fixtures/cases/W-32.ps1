# W-32 케이스. 가이드: 양호 = DNS 미사용 또는 동적 업데이트 "없음" / 취약 = 사용하며 동적 업데이트 설정. 조치는 manual.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) if (Test-CaseDnsZone) { Remove-DnsServerZone -Name 'kisa-case.test' -Force } } })
    States    = [ordered]@{
        'dns-stopped'       = @{ Svc = @{ DNS = 'Stopped' } }
        'dynamic-nonsecure' = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                if (-not (Test-CaseDnsZone)) { Add-DnsServerPrimaryZone -Name 'kisa-case.test' -ZoneFile 'kisa-case.test.dns' }
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -DynamicUpdate NonsecureAndSecure
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.AllowUpdate -eq 1) { $true } else { "AllowUpdate=$($z.AllowUpdate)" } }
        }
        'dynamic-none'      = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                if (-not (Test-CaseDnsZone)) { Add-DnsServerPrimaryZone -Name 'kisa-case.test' -ZoneFile 'kisa-case.test.dns' }
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -DynamicUpdate None
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.AllowUpdate -eq 0) { $true } else { "AllowUpdate=$($z.AllowUpdate)" } }
        }
    }
}

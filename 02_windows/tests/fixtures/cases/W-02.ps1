# W-02 케이스. 가이드: 양호 = Guest 비활성화 / 취약 = 활성화
@{
    Resources = @(@{
            Save    = { (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).Enabled }
            Restore = { param($e) $u = Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }; if ($e) { Enable-LocalUser -SID $u.SID } else { Disable-LocalUser -SID $u.SID } }
        })
    States    = [ordered]@{
        'guest-enabled'  = @{
            Set   = { Enable-LocalUser -SID (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).SID }
            Check = { $e = (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).Enabled; if ($e) { $true } else { "Enabled=$e" } }
        }
        'guest-disabled' = @{
            Set   = { Disable-LocalUser -SID (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).SID }
            Check = { $e = (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).Enabled; if (-not $e) { $true } else { "Enabled=$e" } }
        }
    }
    Fix       = @{ From = 'guest-enabled' }
}

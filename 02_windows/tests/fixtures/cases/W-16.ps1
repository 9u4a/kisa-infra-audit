# W-16 케이스. 가이드: 양호 = 일반 공유가 없거나 공유 권한에 Everyone 없음 / 취약 = 일반 공유 권한에 Everyone 있음
@{
    Resources = @(@{
            Save    = { $null }
            Restore = {
                param($x)
                if (Get-SmbShare -Name 'kisa_case16' -ErrorAction SilentlyContinue) { Remove-SmbShare -Name 'kisa_case16' -Force }
                Remove-Item -Recurse -Force (Join-Path $env:SystemDrive 'kisa_case\share16') -ErrorAction SilentlyContinue
            }
        })
    States    = [ordered]@{
        'everyone-share' = @{
            Set   = {
                $dir = Join-Path $env:SystemDrive 'kisa_case\share16'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $everyone = (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value
                New-SmbShare -Name 'kisa_case16' -Path $dir -FullAccess $everyone | Out-Null
            }
            Check = { $a = @(Get-SmbShareAccess -Name 'kisa_case16' | Where-Object { $_.AccountName -eq 'Everyone' -and $_.AccessControlType -eq 0 }); if ($a.Count -gt 0) { $true } else { "Everyone 권한 없음" } }
        }
        'admin-share'    = @{
            Set   = {
                $dir = Join-Path $env:SystemDrive 'kisa_case\share16'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $admins = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
                New-SmbShare -Name 'kisa_case16' -Path $dir -FullAccess $admins | Out-Null
            }
            Check = {
                $s = Get-SmbShare -Name 'kisa_case16' -ErrorAction SilentlyContinue
                $a = @(Get-SmbShareAccess -Name 'kisa_case16' | Where-Object { $_.AccountName -eq 'Everyone' })
                if ($s -and $a.Count -eq 0) { $true } else { "share=$([bool]$s) everyone=$($a.Count)" }
            }
        }
    }
    Fix       = @{ From = 'everyone-share' }
}

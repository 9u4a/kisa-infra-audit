# W-16 케이스. 가이드: 양호 = 일반 공유가 없거나 공유 권한에 Everyone 없음 / 취약 = 일반 공유 권한에 Everyone 있음
# A7: 사용자가 만든 숨김 공유(이름이 $ 로 끝남)도 일반 공유다 - 'hidden-everyone-share' 가 예전 거짓 GOOD 의 재현
@{
    Resources = @(@{
            Save    = { $null }
            Restore = {
                param($x)
                foreach ($n in @('kisa_case16', 'kisa_case16$')) { if (Get-SmbShare -Name $n -ErrorAction SilentlyContinue) { Remove-SmbShare -Name $n -Force } }
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
        'hidden-everyone-share' = @{
            Set   = {
                $dir = Join-Path $env:SystemDrive 'kisa_case\share16'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $everyone = (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value
                New-SmbShare -Name 'kisa_case16$' -Path $dir -FullAccess $everyone | Out-Null
            }
            Check = {
                $s = Get-SmbShare -Name 'kisa_case16$' -ErrorAction SilentlyContinue
                $a = @(Get-SmbShareAccess -Name 'kisa_case16$' | Where-Object { $_.AccountName -eq 'Everyone' -and $_.AccessControlType -eq 0 })
                if ($s -and -not $s.Special -and $a.Count -gt 0) { $true } else { "share=$([bool]$s) special=$($s.Special) everyone=$($a.Count)" }
            }
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

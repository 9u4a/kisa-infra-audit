# W-46 케이스. 가이드: 양호 = SAM 파일 접근 권한이 Administrators, System 에만 / 취약 = 그 외 그룹에 권한
@{
    Resources = @(@{ Save = { Save-CaseAcl (Join-Path $env:SystemRoot 'System32\config\SAM') }; Restore = { param($o) Restore-CaseAcl $o } })
    States    = [ordered]@{
        'users-read'   = @{
            Set   = { Invoke-CaseIcacls @((Join-Path $env:SystemRoot 'System32\config\SAM'), '/grant', '*S-1-5-32-545:(R)') }
            Check = { if (Test-CaseAclHasSid -Path (Join-Path $env:SystemRoot 'System32\config\SAM') -Sid 'S-1-5-32-545') { $true } else { "Users ACE 없음" } }
        }
        'default-acl'  = @{
            Check = { if (-not (Test-CaseAclHasSid -Path (Join-Path $env:SystemRoot 'System32\config\SAM') -Sid 'S-1-5-32-545')) { $true } else { "Users ACE 있음" } }
        }
    }
    Fix       = @{ From = 'users-read' }
}

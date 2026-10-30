# W-06 케이스. 가이드: 양호 = Administrators 구성원 1명 이하 또는 불필요한 관리자 없음 / 취약 = 불필요한 관리자 계정 존재.
# "불필요" 여부는 조직 판단이라 2명 이상이면 MANUAL(manual-by-design) - 1명 이하면 GOOD.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Remove-CaseLocalUser 'kisa_case_adm2' } })
    States    = [ordered]@{
        'one-admin'  = @{
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-544').Count; if ($n -le 1) { $true } else { "members=$n" } }
        }
        'two-admins' = @{
            Set   = { New-CaseLocalUser 'kisa_case_adm2'; Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'kisa_case_adm2' }
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-544').Count; if ($n -ge 2) { $true } else { "members=$n" } }
        }
    }
}

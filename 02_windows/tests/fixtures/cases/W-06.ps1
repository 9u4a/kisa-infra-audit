# W-06 케이스. 가이드: 양호 = Administrators 구성원 1명 이하 또는 불필요한 관리자 없음 / 취약 = 불필요한 관리자 계정 존재.
# "불필요" 여부는 조직 판단이라 2명 이상이면 MANUAL(manual-by-design) - 1명 이하면 GOOD.
# one-admin 은 예전에 러너 기본값(구성원 1명)에 기댔는데 Server 2022 러너는 기본 구성원이 2명이라 깨졌다(C3) - 실행 계정만 남기고
# 나머지를 잠시 빼서 만든다(실행 중인 프로세스의 관리자 토큰은 그대로라 하네스는 계속 관리자). 원복은 Resources 가 다시 넣는다.
@{
    Resources = @(
        @{ Save = { $null }; Restore = { param($x) Remove-CaseLocalUser 'kisa_case_adm2' } },
        @{
            Save    = { $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                @(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { "$($_.SID)" -ne $me } | ForEach-Object { "$($_.SID)" }) }
            Restore = { param($s) foreach ($sid in @($s | Where-Object { $_ })) {   # 다른 구성원이 없으면(Server 2025) 저장값이 $null
                    if (-not (Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { "$($_.SID)" -eq $sid })) { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $sid } } }
        }
    )
    States    = [ordered]@{
        'one-admin'  = @{
            Set   = { $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { "$($_.SID)" -ne $me } | ForEach-Object { Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member "$($_.SID)" } }
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-544').Count; if ($n -le 1) { $true } else { "members=$n" } }
        }
        'two-admins' = @{
            Set   = { New-CaseLocalUser 'kisa_case_adm2'; Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'kisa_case_adm2' }
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-544').Count; if ($n -ge 2) { $true } else { "members=$n" } }
        }
    }
}

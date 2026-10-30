# W-01 케이스(형식: 02_windows/tests/case_runner.ps1 머리말). 가이드: 양호 = 이름 변경 또는 강화된 비밀번호 / 취약 = 이름 미변경 및 단순 비밀번호.
# 이름을 바꾼 직전에는 Win32_UserAccount(진단이 쓰는 WMI) 조회가 잠시 실패할 수 있어(CI run 41011236012) Check 가 WMI 로 새 이름이 보일 때까지 기다린다.
# 비밀번호 강도는 평문 없이 판정할 수 없어(로그온 시도는 계정 잠금 위험 - S3) 이름이 기본값이면 MANUAL(manual-by-design).
@{
    Resources = @(@{
            Save    = { (Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }).Name }
            Restore = { param($n) $u = Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }; if ($u.Name -ne $n) { Rename-LocalUser -SID $u.SID -NewName $n } }
        })
    States    = [ordered]@{
        'default-name' = @{
            Set   = { $u = Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }; if ($u.Name -ne 'Administrator') { Rename-LocalUser -SID $u.SID -NewName 'Administrator' } }
            Check = { Wait-CaseAdminName 'Administrator' }
        }
        # 러너의 빌트인 관리자는 이미 runneradmin 으로 바뀌어 있다 - 로그온 중인 계정을 다른 이름으로 또 바꾸지 않고 기준 상태를 쓴다
        'renamed'      = @{
            Check = { $n = (Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }).Name; if ($n -and $n -ne 'Administrator') { $true } else { "name=$n" } }
        }
    }
}

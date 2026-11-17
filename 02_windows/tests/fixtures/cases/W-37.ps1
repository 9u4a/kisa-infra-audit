# W-37 케이스(1.7.0 값 지정 조치). 가이드: 불필요한 예약 작업 제거 - 의심 여부는 사람이 판단하므로 진단은 MANUAL.
# 조치는 정책 값(W-37.tasks)에 적은 작업만 비활성화하고, 지정하지 않은 작업은 그대로여야 한다.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) foreach ($n in 'old', 'keep') { Unregister-ScheduledTask -TaskPath '\kisa_case\' -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue } } })
    States    = [ordered]@{
        'custom-tasks' = @{
            Set   = {
                $a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0'
                foreach ($n in 'old', 'keep') { Register-ScheduledTask -TaskPath '\kisa_case\' -TaskName $n -Action $a -Force | Out-Null }
            }
            Check = {
                $s = @('old', 'keep' | ForEach-Object { (Get-ScheduledTask -TaskPath '\kisa_case\' -TaskName $_ -ErrorAction SilentlyContinue).State })
                if (($s -join ',') -eq 'Ready,Ready') { $true } else { "state=$($s -join ',')" }
            }
        }
    }
    Fix       = @{
        From = 'custom-tasks'; Expect = 'MANUAL'; Params = @{ tasks = @('\kisa_case\old') }
        Verify = {
            $o = (Get-ScheduledTask -TaskPath '\kisa_case\' -TaskName 'old').State; $k = (Get-ScheduledTask -TaskPath '\kisa_case\' -TaskName 'keep').State
            if ("$o" -eq 'Disabled' -and "$k" -eq 'Ready') { $true } else { "old=$o keep=$k" }
        }
    }
    # 값 검증 거부: OS 기본 작업(\Microsoft\Windows\)은 값에 있어도 바꾸지 않는다
    FixReject = @{ From = 'custom-tasks'; Params = @{ tasks = @('\kisa_case\old', '\Microsoft\Windows\Defrag\ScheduledDefrag') } }
}

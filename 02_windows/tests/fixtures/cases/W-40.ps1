# W-40 케이스. 가이드: 양호 = 감사 정책 권고 기준(계정 관리·디렉터리 서비스 액세스 실패, 계정 로그온·권한 사용·로그온·정책 변경 성공/실패)대로 설정 /
# 취약 = 그렇지 않음. 조치는 감사 정책을 되돌리지 못한다(Register-FixNoRollback) - 원복 후 판정은 GOOD, audit 범위 차이는 참고.
@{
    Resources = @(@{
            Save    = { $f = Join-Path $global:CaseTmpRoot ("audit_" + [guid]::NewGuid().ToString("N") + ".csv"); & auditpol.exe /backup /file:$f | Out-Null; if ($LASTEXITCODE -ne 0) { throw "auditpol /backup 실패" }; $f }
            Restore = { param($f) & auditpol.exe /restore /file:$f | Out-Null; if ($LASTEXITCODE -ne 0) { throw "auditpol /restore 실패" } }
        })
    States    = [ordered]@{
        'recommended'        = @{
            Set   = { foreach ($g in @('{0CCE923A-69AE-11D9-BED3-505054503030}', '{0CCE923F-69AE-11D9-BED3-505054503030}', '{0CCE9228-69AE-11D9-BED3-505054503030}', '{0CCE9215-69AE-11D9-BED3-505054503030}', '{0CCE922F-69AE-11D9-BED3-505054503030}')) { Set-CaseAudit -Guid $g -Success $true -Failure $true }; Set-CaseAudit -Guid '{0CCE923B-69AE-11D9-BED3-505054503030}' -Success $false -Failure $true }
            Check = { $bad = @(foreach ($g in @('{0CCE923A-69AE-11D9-BED3-505054503030}', '{0CCE923F-69AE-11D9-BED3-505054503030}', '{0CCE9228-69AE-11D9-BED3-505054503030}', '{0CCE9215-69AE-11D9-BED3-505054503030}', '{0CCE922F-69AE-11D9-BED3-505054503030}')) { $v = Get-CaseAuditSetting $g; if ($v -ne 'Success and Failure') { "$g=$v" } }); $ds = Get-CaseAuditSetting '{0CCE923B-69AE-11D9-BED3-505054503030}'; if ($ds -ne 'Failure') { $bad += "DS=$ds" }; if ($bad.Count -eq 0) { $true } else { $bad -join ' ' } }
        }
        'logon-success-only' = @{
            Set   = {
                foreach ($g in @('{0CCE923A-69AE-11D9-BED3-505054503030}', '{0CCE923F-69AE-11D9-BED3-505054503030}', '{0CCE9228-69AE-11D9-BED3-505054503030}', '{0CCE922F-69AE-11D9-BED3-505054503030}')) { Set-CaseAudit -Guid $g -Success $true -Failure $true }
                Set-CaseAudit -Guid '{0CCE9215-69AE-11D9-BED3-505054503030}' -Success $true -Failure $false
                Set-CaseAudit -Guid '{0CCE923B-69AE-11D9-BED3-505054503030}' -Success $false -Failure $true
            }
            Check = { $v = Get-CaseAuditSetting '{0CCE9215-69AE-11D9-BED3-505054503030}'; if ($v -eq 'Success') { $true } else { "Logon=$v" } }
        }
        # A10: 나머지 5개는 권고대로인데 디렉터리 서비스 액세스만 감사 안 함 - 예전에는 판정 목록에 없어 GOOD
        'ds-access-none'     = @{
            Set   = { foreach ($g in @('{0CCE923A-69AE-11D9-BED3-505054503030}', '{0CCE923F-69AE-11D9-BED3-505054503030}', '{0CCE9228-69AE-11D9-BED3-505054503030}', '{0CCE9215-69AE-11D9-BED3-505054503030}', '{0CCE922F-69AE-11D9-BED3-505054503030}')) { Set-CaseAudit -Guid $g -Success $true -Failure $true }; Set-CaseAudit -Guid '{0CCE923B-69AE-11D9-BED3-505054503030}' -Success $false -Failure $false }
            Check = { $v = Get-CaseAuditSetting '{0CCE923B-69AE-11D9-BED3-505054503030}'; if ($v -eq 'No Auditing') { $true } else { "DS=$v" } }
        }
    }
    Fix       = @{ From = 'logon-success-only'; AfterRollback = 'GOOD'; SoftAreas = @('audit') }
}

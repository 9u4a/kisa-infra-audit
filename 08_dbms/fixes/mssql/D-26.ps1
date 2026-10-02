# D-26 (상) 감사 기록 설정 [MSSQL] — 조치 [fix: confirm]
# checks/mssql/D-26.ps1: 취약 = 서버 감사(Server Audit)가 없거나 비활성화됨. 서버 감사 객체
# 생성/활성화는(PostgreSQL/Oracle 의 logging_collector/audit_trail 과 달리) 인스턴스 재시작이
# 필요 없는 런타임 조작이라 재시작 없이 바로 재검증을 통과할 수 있다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_state_enabled FROM sys.server_audits;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MSSQL 연결/쿼리 실패: $err"; $Global:FixEvidence = ""
    return
}

if (-not $out) {
    # 감사 객체가 전혀 없음 - 기본 로그 대상(Windows 애플리케이션 로그)으로 새로 생성한다.
    # 원복 시 SERVER AUDIT SPECIFICATION 이 먼저 꺼지고 제거되어야 그 뒤의 SERVER AUDIT를
    # DROP 할 수 있다(참조 중인 감사는 DROP 불가) - 순서를 지키지 않으면 DROP 이 조용히
    # 실패해 원복이 되지 않는 버그가 있었다(MSSQL Docker 실기 테스트로 발견).
    Add-FixDbRollback -Sql "IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'KISA_D26_AuditSpec') BEGIN ALTER SERVER AUDIT SPECIFICATION KISA_D26_AuditSpec WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION KISA_D26_AuditSpec; END IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'KISA_D26_Audit') BEGIN ALTER SERVER AUDIT KISA_D26_Audit WITH (STATE = OFF); DROP SERVER AUDIT KISA_D26_Audit; END"
    Invoke-MssqlQuery -Sql "CREATE SERVER AUDIT KISA_D26_Audit TO APPLICATION_LOG;" | Out-Null
    Invoke-MssqlQuery -Sql "ALTER SERVER AUDIT KISA_D26_Audit WITH (STATE = ON);" | Out-Null
    Invoke-MssqlQuery -Sql "CREATE SERVER AUDIT SPECIFICATION KISA_D26_AuditSpec FOR SERVER AUDIT KISA_D26_Audit ADD (FAILED_LOGIN_GROUP), ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON);" | Out-Null
} else {
    $disabled = @($out) | Where-Object { ($_ -split '\|')[1].Trim() -eq "0" }
    foreach ($row in $disabled) {
        $name = ($row -split '\|')[0].Trim()
        if (-not $name) { continue }
        Add-FixDbRollback -Sql "ALTER SERVER AUDIT [$name] WITH (STATE = OFF);"
        Invoke-MssqlQuery -Sql "ALTER SERVER AUDIT [$name] WITH (STATE = ON);" | Out-Null
    }
}

$check = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_state_enabled FROM sys.server_audits;"
$enabled = @($check) | Where-Object { ($_ -split '\|')[1].Trim() -eq "1" }
if ($enabled) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "서버 감사를 생성/활성화함: $($check -join '; ')"
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "서버 감사 활성화 실패"
}
$Global:FixEvidence = ""

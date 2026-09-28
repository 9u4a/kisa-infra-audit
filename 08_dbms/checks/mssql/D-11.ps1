# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
# master 데이터베이스의 시스템 객체(is_ms_shipped=1)에 public/guest 에게 명시적으로 부여된
# 권한이 있으면 취약으로 판단한다.
# 주의(실기 테스트로 확인한 버그 2건):
#  1) "USE master;" 를 별도 statement로 실행하면 sqlcmd가 "Changed database context to
#     'master'." 안내 메시지를 결과에 섞어 출력해 항상 "결과 있음"으로 오판된다 - USE 없이
#     master.sys.* 3-part naming 으로 조회해 이 메시지 자체가 나오지 않게 한다.
#  2) spt_fallback_db/spt_fallback_dev/spt_fallback_usg/spt_values/spt_monitor 는 Microsoft가
#     기본으로 PUBLIC 에 SELECT 를 부여해 배포하는 레거시 호환용 테이블이라 오탐 대상에서 제외한다.
$sql = "SET NOCOUNT ON; SELECT dp.name, o.name, p.permission_name FROM master.sys.database_permissions p JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id JOIN master.sys.objects o ON p.major_id = o.object_id WHERE o.is_ms_shipped = 1 AND dp.name IN ('public','guest') AND p.state = 'G' AND o.name NOT IN ('spt_fallback_db','spt_fallback_dev','spt_fallback_usg','spt_values','spt_monitor');"
$out = Invoke-MssqlQuery -Sql $sql
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-11" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
if ($out) {
    return New-CheckResult -Code "D-11" -Status "VULN" -Detail "public/guest 에게 시스템 객체(master)에 대한 명시적 권한이 부여되어 있음" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-11" -Status "GOOD" -Detail "public/guest 에게 부여된 시스템 객체(master) 권한이 없음" -Evidence ""
}

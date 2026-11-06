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
# 외부 검수 A15: master.sys.objects 는 sys 스키마 시스템 객체(음수 object_id - 카탈로그 뷰·확장 프로시저·시스템 기본 테이블)를
# 담지 않아(C-D23 과 같은 원인) 그쪽 권한은 보지 못했고, WITH GRANT OPTION(state='W') 부여도 빠졌다. master.sys.all_objects 로 바꾸되
# public 은 SQL Server 가 기본으로 sys 카탈로그 뷰 SELECT·일부 확장 프로시저 EXECUTE 를 부여해 배포하므로(D-24 러너 실측 xp_regread)
# 그 기본값까지 취약으로 보지 않도록 "dbo 등 일반 스키마의 ms_shipped 객체(양수 id)와 시스템 기본 테이블(type S)" 로 한정한다
# (가이드 조치 Step 2: 시스템 정보는 카탈로그·information_schema 뷰로 접근). guest 는 기본 부여가 없어 모든 시스템 객체를 본다.
$sql = "SET NOCOUNT ON; SELECT dp.name, s.name + '.' + o.name, p.permission_name, p.state FROM master.sys.database_permissions p JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id JOIN master.sys.all_objects o ON p.major_id = o.object_id JOIN master.sys.schemas s ON s.schema_id = o.schema_id WHERE p.class = 1 AND o.is_ms_shipped = 1 AND p.state IN ('G','W') AND (dp.name = 'guest' OR (dp.name = 'public' AND (o.object_id > 0 OR o.type = 'S'))) AND o.name NOT IN ('spt_fallback_db','spt_fallback_dev','spt_fallback_usg','spt_values','spt_monitor');"
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

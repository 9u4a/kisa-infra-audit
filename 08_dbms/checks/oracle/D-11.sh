# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
# deviation: 가이드 원문이 제시한 조회 쿼리는 특정 버전 시점의 Oracle 내장 롤 이름을 정적으로
# 나열한 예외 목록을 쓰는데, Oracle 19c/21c/23c 이후 추가된 내장 롤(GSMADMIN_INTERNAL, XDB,
# AUDIT_ADMIN 등 수십 개)이 그 목록에 없어 대량 오탐이 발생함을 Docker(gvenzl/oracle-free 23ai)
# 실기 테스트로 확인. grantee 가 실제 "사용자 계정"(dba_users, oracle_maintained='N')인 경우만
# 검사하도록 조건을 바꿔 같은 취지(DBA 외 일반 계정 접근 차단)를 버전에 관계없이 판정한다.
run_check() {
    sql="SELECT DISTINCT tp.grantee FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE (tp.owner = 'SYS' OR tp.table_name LIKE 'DBA_%') AND tp.privilege != 'EXECUTE' AND u.oracle_maintained = 'N' AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') ORDER BY tp.grantee;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="DBA 외 계정이 시스템 테이블(SYS 소유/DBA_%)에 권한을 보유함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="시스템 테이블 권한이 DBA(관리자) 계정으로 제한되어 있음"
    fi
}

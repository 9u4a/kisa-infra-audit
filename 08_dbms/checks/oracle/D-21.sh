# D-21 (중) 인가되지 않은 GRANT OPTION 사용 제한 [Oracle]
# 판단 기준(가이드 원문): 양호 = WITH GRANT OPTION이 필요한 Role 에만 설정된 경우
#                        취약 = 그렇지 않은 경우 (일반 계정에 GRANTABLE='YES')
# deviation: D-11과 동일한 이유로 owner 예외를 정적 나열하는 대신 grantee가 실제 사용자 계정
# (dba_users, oracle_maintained='N')인 경우만 검사한다(Oracle 내장 계정/롤 오탐 방지, Docker
# gvenzl/oracle-free 23ai 실기 테스트로 확인).
run_check() {
    sql="SELECT DISTINCT tp.grantee, tp.owner, tp.table_name FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE tp.grantable = 'YES' AND u.oracle_maintained = 'N' AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') ORDER BY tp.grantee;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="DBA가 아닌 계정에 WITH GRANT OPTION(grantable=YES) 권한이 부여되어 있음"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="DBA 외 계정에 부여된 GRANT OPTION이 없음"
    fi
}

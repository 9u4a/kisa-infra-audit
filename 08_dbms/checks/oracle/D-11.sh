# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
# deviation: 가이드 원문이 제시한 조회 쿼리는 특정 버전 시점의 Oracle 내장 롤 이름을 정적으로
# 나열한 예외 목록을 쓰는데, Oracle 19c/21c/23c 이후 추가된 내장 롤(GSMADMIN_INTERNAL, XDB,
# AUDIT_ADMIN 등 수십 개)이 그 목록에 없어 대량 오탐이 발생함을 Docker(gvenzl/oracle-free 23ai)
# 실기 테스트로 확인. grantee 가 실제 "사용자 계정"(dba_users, oracle_maintained='N')인 경우만
# 검사하도록 조건을 바꿔 같은 취지(DBA 외 일반 계정 접근 차단)를 버전에 관계없이 판정한다.
# 외부 검수 A16: 위 조건이 grantee 를 dba_users 로만 한정해, 사용자 정의 롤(dba_roles.oracle_maintained='N')에 SYS 테이블 권한을
# 주고 그 롤을 일반 계정에 부여한 경우를 놓쳤다. 가이드 원문 쿼리도 내장 롤만 예외로 두고 "계정이나 role 이 나타나면 취약"이므로
# 사용자 정의 롤도 grantee 로 본다(Oracle 내장 롤은 원문 예외 목록과 같은 취지로 계속 제외). 롤이면 그 롤을 (중첩 롤을 거쳐)
# 받은 계정을 dba_role_privs 계층 조회로 근거에 함께 남긴다.
run_check() {
    where="(tp.owner = 'SYS' OR tp.table_name LIKE 'DBA_%') AND tp.privilege != 'EXECUTE' AND (tp.grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N') OR tp.grantee IN (SELECT role FROM dba_roles WHERE oracle_maintained = 'N')) AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA')"
    # DISTINCT 와 스칼라 서브쿼리(CASE ... IN (SELECT ...))를 함께 ORDER BY 하면 ORA-01791 - 롤 여부는 외부 조인으로 표시한다
    sql="SELECT g FROM (SELECT DISTINCT tp.grantee || NVL2(r.role, ' (ROLE)', NULL) AS g FROM dba_tab_privs tp LEFT JOIN dba_roles r ON r.role = tp.grantee WHERE $where) ORDER BY g;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if printf '%s\n' "$out" | grep -q '(ROLE)'; then
        # 근거 보강(판정에는 쓰지 않음): 해당 롤을 직접·중첩 롤로 받은 계정
        holders=$(oracle_query "SELECT DISTINCT rp.grantee || ' <- ' || CONNECT_BY_ROOT rp.granted_role FROM dba_role_privs rp WHERE rp.grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N') START WITH rp.granted_role IN (SELECT DISTINCT tp.grantee FROM dba_tab_privs tp WHERE $where AND tp.grantee IN (SELECT role FROM dba_roles)) CONNECT BY NOCYCLE PRIOR rp.grantee = rp.granted_role ORDER BY 1;" 2>/dev/null) \
            || holders="(롤 보유 계정 조회 실패)"
        CHECK_EVIDENCE="$out
[롤 보유 계정(중첩 포함)]
${holders:-(없음)}"
    fi
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="DBA 외 계정 또는 사용자 정의 롤이 시스템 테이블(SYS 소유/DBA_%)에 권한을 보유함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="시스템 테이블 권한이 DBA(관리자) 계정으로 제한되어 있음(일반 계정·사용자 정의 롤 직접 부여 없음)"
    fi
}

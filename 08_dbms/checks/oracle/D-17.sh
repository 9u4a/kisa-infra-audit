# D-17 (하) Audit Table은 데이터베이스 관리자 계정으로 접근하도록 제한 [Oracle]
# 판단 기준(가이드 원문): 양호 = Audit Table 접근 권한이 관리자 계정으로 설정된 경우
#                        취약 = 일반 계정으로 설정된 경우
run_check() {
    owner=$(oracle_query "SELECT owner FROM dba_tables WHERE table_name = 'AUD\$';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $owner"; CHECK_EVIDENCE="$owner"
        return
    fi
    owner_t=$(printf '%s' "$owner" | tr -d ' \r')
    if [ -z "$owner_t" ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="AUD\$ 감사 테이블이 존재하지 않음(감사 미설정)"; CHECK_EVIDENCE=""
        return
    fi
    grants=$(oracle_query "SELECT grantee, privilege FROM dba_tab_privs WHERE table_name = 'AUD\$' AND grantee NOT IN ('SYS','SYSTEM') ORDER BY grantee;")
    CHECK_EVIDENCE="owner=$owner_t
$grants"
    if [ "$owner_t" = "SYS" ] && [ -z "$grants" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="AUD\$ 테이블 소유자가 SYS 이고 일반 계정에 부여된 권한이 없음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="AUD\$ 테이블에 SYS/SYSTEM 외 계정의 접근 권한이 존재함"
    fi
}

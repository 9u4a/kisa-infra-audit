# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [Oracle]
# 판단 기준(가이드 원문): 양호 = 기본 계정의 초기 비밀번호를 변경하거나 잠금설정한 경우
#                        취약 = 초기 비밀번호를 변경하지 않거나 잠금설정을 하지 않은 경우
# 자동화 범위(1.4.0, D-C1): 예전에는 가이드가 나열한 기본 계정 중 OPEN 인 것이 있으면 무조건 취약이었다. SYSTEM 은
# 필수 관리 계정이라 항상 OPEN 이고 조치(fixes/oracle/D-01.sh)도 잠그지 않으므로, 비밀번호를 바꾼 정상 서버도 영구히
# VULN 이었고 조치는 매번 재검증 VULN → 원복으로 끝났다(Docker gvenzl 26ai 실기). 가이드 기준은 "초기 비밀번호를 변경
# 하거나 잠금" 이므로, Oracle 이 제공하는 DBA_USERS_WITH_DEFPWD(초기 비밀번호를 그대로 쓰는 계정 - 해시 비교, 11g 이상)
# 와 잠금 상태를 함께 본다: 초기 비밀번호 그대로 + OPEN 인 계정이 있으면 취약. 가이드가 나열한 기본 계정 목록은
# 증적으로 함께 남긴다. 뷰를 조회하지 못하면(권한 부족 등) 판정하지 않고 ERROR.
run_check() {
    _accts="'SCOTT','SYSTEM','DBSNMP','OUTLN','TRACESVR','ORDPLUGINS','ORDSYS','CTXSYS','MDSYS','ADAMS','BLAKE','CLARK','JONES','LBACSYS'"
    out=$(oracle_query "SELECT u.username || '|' || u.account_status FROM dba_users u WHERE u.account_status = 'OPEN' AND u.username IN (SELECT d.username FROM dba_users_with_defpwd d) ORDER BY u.username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패(DBA_USERS_WITH_DEFPWD 조회 권한 필요): $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    listed=$(oracle_query "SELECT username || '|' || account_status FROM dba_users WHERE username IN ($_accts) ORDER BY username;" 2>/dev/null)
    CHECK_EVIDENCE="[초기 비밀번호 그대로이고 잠기지 않은 계정(DBA_USERS_WITH_DEFPWD ∩ OPEN)]
${out:-(없음)}
[가이드 나열 기본 계정 상태]
$listed"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="초기 비밀번호를 바꾸지 않은 기본 계정이 잠기지 않은(OPEN) 상태임: $(printf '%s' "$out" | cut -d'|' -f1 | tr -d ' ' | tr '\n' ' ')"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="잠기지 않은 기본 계정은 모두 초기 비밀번호가 변경되어 있음(초기 비밀번호 그대로인 계정은 잠김)"
    fi
}

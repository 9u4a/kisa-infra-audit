# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [Oracle]
# 판단 기준(가이드 원문): 양호 = 기본 계정의 초기 비밀번호를 변경하거나 잠금설정한 경우
#                        취약 = 초기 비밀번호를 변경하지 않거나 잠금설정을 하지 않은 경우
# 자동화 범위: 가이드 원문이 나열한 Oracle 기본(데모) 계정들의 ACCOUNT_STATUS 를 조회해,
# 활성(OPEN) 상태인 기본 계정이 있으면 취약으로 본다(비밀번호가 실제로 바뀌었는지는 해시만으로
# 확인 불가하므로, "잠기지 않은 기본 계정 존재" 자체를 위험 신호로 삼는다).
run_check() {
    _accts="'SCOTT','SYSTEM','DBSNMP','OUTLN','TRACESVR','ORDPLUGINS','ORDSYS','CTXSYS','MDSYS','ADAMS','BLAKE','CLARK','JONES','LBACSYS'"
    out=$(oracle_query "SELECT username, account_status FROM dba_users WHERE username IN ($_accts) AND account_status = 'OPEN' ORDER BY username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="잠기지 않은(OPEN) 기본/데모 계정이 존재함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="가이드에서 나열한 기본/데모 계정 중 활성 상태인 것이 없음"
    fi
}

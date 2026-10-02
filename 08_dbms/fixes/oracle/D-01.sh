# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [Oracle] — 조치 [fix: confirm]
# checks/oracle/D-01.sh 가 찾아낸 OPEN 상태의 기본/데모 계정을 잠근다(비밀번호를 추측해 바꾸는
# 대신 계정 잠금 - 가이드가 제시한 두 대안 중 스크립트가 안전하게 할 수 있는 쪽).
run_fix() {
    _accts="'SCOTT','SYSTEM','DBSNMP','OUTLN','TRACESVR','ORDPLUGINS','ORDSYS','CTXSYS','MDSYS','ADAMS','BLAKE','CLARK','JONES','LBACSYS'"
    out=$(oracle_query "SELECT username FROM dba_users WHERE username IN ($_accts) AND account_status = 'OPEN' ORDER BY username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="Oracle 연결/쿼리 실패: $out"; FIX_EVIDENCE=""
        return
    fi
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="OPEN 상태인 기본/데모 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for u in $out; do
        IFS=$old_ifs
        u=$(printf '%s' "$u" | tr -d ' \r')
        [ -z "$u" ] && { IFS='
'; continue; }
        [ "$u" = "SYSTEM" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "ALTER USER $u ACCOUNT UNLOCK;"
        oracle_query "ALTER USER $u ACCOUNT LOCK;" >/dev/null 2>&1
        applied="$applied $u"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="OPEN 상태였던 기본/데모 계정을 잠금함:$applied (SYSTEM 계정은 필수 관리 계정이라 제외 - 잠그면 관리 자체가 불가능해지므로 잠재적 lockout 위험 방지)"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="SYSTEM 외 잠글 대상 계정이 없음"
    fi
    FIX_EVIDENCE=""
}

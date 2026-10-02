# D-18 (상) 응용프로그램 또는 DBA 계정의 Role이 Public으로 설정되지 않도록 조정 [Oracle] — 조치 [fix: auto]
run_fix() {
    out=$(oracle_query "SELECT granted_role FROM dba_role_privs WHERE grantee = 'PUBLIC';")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="PUBLIC 에게 부여된 Role이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for role in $out; do
        IFS=$old_ifs
        role=$(printf '%s' "$role" | tr -d ' \r')
        [ -z "$role" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $role TO PUBLIC;"
        oracle_query "REVOKE $role FROM PUBLIC;" >/dev/null 2>&1
        applied="$applied $role"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="PUBLIC 에서 Role 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="Role 회수 실패"
    fi
    FIX_EVIDENCE="$out"
}

# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [Oracle] — 조치 [fix: auto]
# checks/oracle/D-11.sh 와 동일한 조건(oracle_maintained='N')으로 찾아낸 (owner, table, privilege,
# grantee) 조합을 정확히 그 권한만 회수한다.
run_fix() {
    sql="SELECT tp.owner, tp.table_name, tp.privilege, tp.grantee FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE (tp.owner = 'SYS' OR tp.table_name LIKE 'DBA_%') AND tp.privilege != 'EXECUTE' AND u.oracle_maintained = 'N' AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') ORDER BY tp.grantee;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="Oracle 연결/쿼리 실패: $out"; FIX_EVIDENCE=""
        return
    fi
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="DBA 외 계정의 시스템 테이블 권한이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for line in $out; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        owner=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$1); print $1}')
        tbl=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
        priv=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
        grantee=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
        [ -z "$owner" ] || [ -z "$tbl" ] || [ -z "$priv" ] || [ -z "$grantee" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $priv ON $owner.$tbl TO $grantee;"
        oracle_query "REVOKE $priv ON $owner.$tbl FROM $grantee;" >/dev/null 2>&1
        applied="$applied $grantee($owner.$tbl:$priv)"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="시스템 테이블 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패(결과 파싱 실패 가능)"
    fi
    FIX_EVIDENCE="$out"
}

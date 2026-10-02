# D-21 (중) 인가되지 않은 GRANT OPTION 사용 제한 [Oracle] — 조치 [fix: auto]
# checks/oracle/D-21.sh 와 동일한 조건(oracle_maintained='N')으로 찾아낸 GRANT OPTION 을
# 회수한다(REVOKE ... 는 권한 자체와 GRANT OPTION 을 함께 제거하므로, 재부여 시 WITH GRANT
# OPTION 없이 다시 GRANT 해야 GRANT OPTION 없는 권한만 남는다 - 원복 SQL도 이를 반영).
run_fix() {
    sql="SELECT DISTINCT tp.grantee, tp.owner, tp.table_name, tp.privilege FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE tp.grantable = 'YES' AND u.oracle_maintained = 'N' AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') ORDER BY tp.grantee;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="Oracle 연결/쿼리 실패: $out"; FIX_EVIDENCE=""
        return
    fi
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="DBA 외 계정에 부여된 GRANT OPTION이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for line in $out; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        grantee=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$1); print $1}')
        owner=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
        tbl=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
        priv=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
        [ -z "$grantee" ] || [ -z "$owner" ] || [ -z "$tbl" ] || [ -z "$priv" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $priv ON $owner.$tbl TO $grantee WITH GRANT OPTION;"
        oracle_query "REVOKE $priv ON $owner.$tbl FROM $grantee;" >/dev/null 2>&1
        oracle_query "GRANT $priv ON $owner.$tbl TO $grantee;" >/dev/null 2>&1
        applied="$applied $grantee($owner.$tbl:$priv)"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="GRANT OPTION 회수(권한 자체는 유지, GRANT OPTION만 제거):$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="GRANT OPTION 회수 실패"
    fi
    FIX_EVIDENCE="$out"
}

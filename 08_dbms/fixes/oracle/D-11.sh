# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [Oracle] — 조치 [fix: auto]
# 변경: DBA 외 일반 계정의 SYS 소유·DBA_* 테이블 권한(EXECUTE 제외)마다 REVOKE <권한> ON <owner.table> FROM <계정>(SYS 소유는 SYSDBA 필요)
# checks/oracle/D-11.sh 와 동일한 조건(계정·롤 oracle_maintained='N')으로 찾아낸 (owner, table, privilege,
# grantee) 조합을 정확히 그 권한만 회수한다. 외부 검수 A16 부터 사용자 정의 롤(oracle_maintained='N')도 대상이다 - 롤에서 회수하면
# 그 롤을 받은 계정 모두 권한을 잃는다(원복 SQL 로 롤에 다시 부여).
run_fix() {
    sql="SELECT tp.owner, tp.table_name, tp.privilege, tp.grantee FROM dba_tab_privs tp WHERE (tp.owner = 'SYS' OR tp.table_name LIKE 'DBA_%') AND tp.privilege != 'EXECUTE' AND (tp.grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N') OR tp.grantee IN (SELECT role FROM dba_roles WHERE oracle_maintained = 'N')) AND tp.grantee NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') ORDER BY tp.grantee;"
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

    applied=""; failed=""
    old_ifs=$IFS; IFS='
'
    for line in $out; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        owner=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$1); print $1}')
        tbl=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$2); print $2}')
        priv=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$3); print $3}')
        grantee=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$4); print $4}')
        [ -z "$owner" ] || [ -z "$tbl" ] || [ -z "$priv" ] || [ -z "$grantee" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $priv ON $owner.$tbl TO $grantee;"
        # 1.4.0(D-C8): 회수 실패를 무시하고 APPLIED 로 보고하던 것을 고쳤다. SYS 소유 객체 권한은 부여자(SYS)만 회수할 수 있어
        # (ORA-01927) SYSTEM 등 계정 접속으로는 실패한다 - OS 인증(/ as sysdba, PDB 는 ORACLE_PDB_SID)으로 실행해야 한다.
        if oracle_query "REVOKE $priv ON $owner.$tbl FROM $grantee;" >/dev/null 2>&1; then
            applied="$applied $grantee($owner.$tbl:$priv)"
        else
            failed="$failed $grantee($owner.$tbl:$priv)($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="${applied:+회수:$applied / }회수 실패(SYS 소유 객체는 SYSDBA 로 실행 필요):$failed"
    elif [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="시스템 테이블 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패(결과 파싱 실패 가능)"
    fi
    FIX_EVIDENCE="$out"
}

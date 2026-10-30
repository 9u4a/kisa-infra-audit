# D-17 (하) Audit Table은 데이터베이스 관리자 계정으로 접근하도록 제한 [Oracle] — 조치 [fix: auto]
run_fix() {
    owner=$(oracle_query "SELECT owner FROM dba_tables WHERE table_name = 'AUD\$';")
    owner_t=$(printf '%s' "$owner" | tr -d ' \r')
    if [ -z "$owner_t" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="AUD\$ 감사 테이블이 존재하지 않음(해당 없음)"; FIX_EVIDENCE=""
        return
    fi

    grants=$(oracle_query "SELECT grantee, privilege FROM dba_tab_privs WHERE table_name = 'AUD\$' AND grantee NOT IN ('SYS','SYSTEM');")
    if [ -z "$grants" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="AUD\$ 에 SYS/SYSTEM 외 부여된 권한이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""; failed=""
    old_ifs=$IFS; IFS='
'
    for line in $grants; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        grantee=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$1); print $1}')
        priv=$(printf '%s' "$line" | awk -F'|' '{gsub(/[ \t\r]/,"",$2); print $2}')
        [ -z "$grantee" ] || [ -z "$priv" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $priv ON SYS.AUD\$ TO $grantee;"
        # 1.4.0(D-C8): 회수 실패를 무시하고 APPLIED 로 보고하던 것을 고쳤다. SYS 소유 객체 권한은 부여자(SYS)만 회수할 수 있어
        # (ORA-01927) SYSTEM 등 계정 접속으로는 실패한다 - OS 인증(/ as sysdba, PDB 는 ORACLE_PDB_SID)으로 실행해야 한다.
        if oracle_query "REVOKE $priv ON SYS.AUD\$ FROM $grantee;" >/dev/null 2>&1; then
            applied="$applied $grantee:$priv"
        else
            failed="$failed $grantee:$priv($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
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
        FIX_DETAIL="AUD\$ 테이블 비인가 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패"
    fi
    FIX_EVIDENCE="$grants"
}

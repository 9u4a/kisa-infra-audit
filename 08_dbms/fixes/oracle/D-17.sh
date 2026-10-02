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

    applied=""
    old_ifs=$IFS; IFS='
'
    for line in $grants; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        grantee=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$1); print $1}')
        priv=$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
        [ -z "$grantee" ] || [ -z "$priv" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "oracle" "GRANT $priv ON SYS.AUD\$ TO $grantee;"
        oracle_query "REVOKE $priv ON SYS.AUD\$ FROM $grantee;" >/dev/null 2>&1
        applied="$applied $grantee:$priv"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="AUD\$ 테이블 비인가 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패"
    fi
    FIX_EVIDENCE="$grants"
}

# D-05 (중) 비밀번호 재사용에 대한 제약 설정 [Oracle] — 조치 [fix: auto]
run_fix() {
    before=$(oracle_query "SELECT resource_name, limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name IN ('PASSWORD_REUSE_TIME','PASSWORD_REUSE_MAX') ORDER BY resource_name;")
    time_before=$(printf '%s\n' "$before" | grep -i PASSWORD_REUSE_TIME | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    max_before=$(printf '%s\n' "$before" | grep -i PASSWORD_REUSE_MAX | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    [ -z "$time_before" ] && time_before="DEFAULT"
    [ -z "$max_before" ] && max_before="DEFAULT"

    fix_db_queue_rollback "oracle" "ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME $time_before PASSWORD_REUSE_MAX $max_before;"
    out=$(oracle_query "ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME 365 PASSWORD_REUSE_MAX 5;" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER PROFILE 실패: $out"; FIX_EVIDENCE="$out"
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="DEFAULT 프로파일에 PASSWORD_REUSE_TIME=365, PASSWORD_REUSE_MAX=5 설정함(변경 전: $time_before/$max_before)"
    FIX_EVIDENCE="$out"
}

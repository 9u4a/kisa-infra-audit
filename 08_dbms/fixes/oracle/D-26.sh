# D-26 (상) 감사 기록 설정 [Oracle] — 조치 [fix: confirm]
# checks/oracle/D-26.sh: 취약 = audit_trail=NONE. audit_trail 은 정적 파라미터라 SPFILE 값을
# 바꿔도 인스턴스 재시작 전까지는 반영되지 않는다 - D-07/D-19 와 동일한 논리로 confirm 등급에서
# 재시작까지 수행한다(DB 클라이언트 연결만 영향, 이 스크립트의 OS 세션에는 영향 없음). SYSDBA
# 세션이 아니면 SHUTDOWN/STARTUP 자체가 거부되므로, 이 fix는 run.sh/fix.sh 가 OS 인증
# ("/ as sysdba", DB_USER 미지정) 으로 접속한 경우에만 재시작까지 성공한다.
run_fix() {
    fix_db_queue_rollback "oracle" "-- D-26: audit_trail SPFILE 값을 DB로 변경함(원본 값을 정확히 알지 못해 기본값 NONE으로 되돌리지 못함)"
    out=$(oracle_query "ALTER SYSTEM SET audit_trail = DB SCOPE=SPFILE;" 2>&1)

    restart_out=$(oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" 2>&1)
    rc=$?

    if [ $rc -eq 0 ]; then
        val=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'audit_trail';" | tr -d ' \r')
        if [ "$val" = "NONE" ] || [ -z "$val" ]; then
            FIX_STATUS="ERROR"
            FIX_DETAIL="재시작은 했으나 audit_trail 이 여전히 NONE 으로 확인됨"
        else
            FIX_STATUS="APPLIED"
            FIX_DETAIL="audit_trail=DB 로 설정하고 인스턴스를 재시작하여 적용함(AUDIT_TRAIL=$val)"
        fi
        FIX_EVIDENCE="audit_trail=$val"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="SPFILE 값은 변경했으나($out) 인스턴스 재시작 실패 - 재시작 전까지는 미반영 상태: $restart_out"
        FIX_EVIDENCE="$restart_out"
    fi
}

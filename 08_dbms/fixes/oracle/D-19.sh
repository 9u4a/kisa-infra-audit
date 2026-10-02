# D-19 (상) OS_ROLES, REMOTE_OS_AUTHENTICATION, REMOTE_OS_ROLES를 FALSE로 설정 [Oracle] — 조치 [fix: confirm]
# 세 파라미터 모두 정적(static) 파라미터라 SPFILE 값을 바꿔도 인스턴스 재시작 전까지는 반영되지
# 않는다 - D-07/D-26 과 동일한 논리로 confirm 등급에서 재시작까지 수행한다(DB 클라이언트 연결만
# 영향, 이 스크립트의 OS 세션에는 영향 없음).
# 주의(Docker 23ai/26ai 실기 테스트로 확인): remote_os_authent 는 최신 Oracle 버전에서 더 이상
# ALTER SYSTEM 으로 설정할 수 없는(ORA-02065) obsolete 파라미터로 보인다 - v$parameter 조회
# 결과에도 아예 나타나지 않았다. 세 ALTER SYSTEM 명령 중 하나가 실패해도 나머지는 계속
# 진행하도록 각각 독립적으로 실행한다(한 파라미터의 실패가 전체를 막지 않게 함).
run_fix() {
    fix_db_queue_rollback "oracle" "-- D-19: os_roles/remote_os_authent/remote_os_roles SPFILE 값을 변경함(원본 값을 정확히 알지 못해 기본값 FALSE로도 되돌리지 못함 - 재시작 전이라 실제로는 아직 미반영 상태일 수 있음)"

    o1=$(oracle_query "ALTER SYSTEM SET os_roles = FALSE SCOPE=SPFILE;" 2>&1)
    o2=$(oracle_query "ALTER SYSTEM SET remote_os_authent = FALSE SCOPE=SPFILE;" 2>&1)
    o3=$(oracle_query "ALTER SYSTEM SET remote_os_roles = FALSE SCOPE=SPFILE;" 2>&1)

    restarted=0
    restart_out=$(oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" 2>&1)
    rc=$?
    [ $rc -eq 0 ] && restarted=1

    if [ "$restarted" -eq 1 ]; then
        val=$(oracle_query "SELECT name, value FROM v\$parameter WHERE name IN ('os_roles','remote_os_authent','remote_os_roles') ORDER BY name;")
        if printf '%s\n' "$val" | grep -qi TRUE; then
            FIX_STATUS="ERROR"
            FIX_DETAIL="재시작은 했으나 일부 값이 여전히 TRUE 로 확인됨: $val"
        else
            FIX_STATUS="APPLIED"
            FIX_DETAIL="SPFILE 값을 FALSE로 설정하고 인스턴스를 재시작하여 적용함"
        fi
        FIX_EVIDENCE="$val"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="SPFILE 값은 변경했으나($o1 / $o2 / $o3) 인스턴스 재시작 실패 - 재시작 전까지는 미반영 상태: $restart_out"
        FIX_EVIDENCE="$restart_out"
    fi
}

# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [Oracle] — 조치 [fix: confirm]
# ALTER PROFILE 은 동적으로 즉시 적용된다(인스턴스 재시작 불필요).
# 주의(Docker 실기 테스트로 발견): "LIMIT ... DEFAULT" 로 원복하면 Oracle의 실제 내장 기본값으로
# 돌아가는데, 최신 버전(23ai/26ai)의 DEFAULT 프로파일 내장 기본값 자체가 UNLIMITED/NULL 이
# 아닐 수 있어 "DEFAULT" 키워드만으로는 조치 이전 값을 정확히 복원하지 못할 수 있다. 조치 전
# 실제 현재 값을 조회해 그 값 그대로 복원하도록 원복 SQL을 구성한다.
run_fix() {
    before=$(oracle_query "SELECT resource_name, limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name IN ('PASSWORD_LIFE_TIME','PASSWORD_VERIFY_FUNCTION') ORDER BY resource_name;")
    life_before=$(printf '%s\n' "$before" | grep -i PASSWORD_LIFE_TIME | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    verify_before=$(printf '%s\n' "$before" | grep -i PASSWORD_VERIFY_FUNCTION | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    [ -z "$life_before" ] && life_before="DEFAULT"
    [ -z "$verify_before" ] || [ "$verify_before" = "NULL" ] && verify_before="NULL"

    fix_db_queue_rollback "oracle" "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME $life_before PASSWORD_VERIFY_FUNCTION $verify_before;"
    out=$(oracle_query "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME 90 PASSWORD_VERIFY_FUNCTION ora12c_verify_function;" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER PROFILE 실패: $out"; FIX_EVIDENCE="$out"
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="DEFAULT 프로파일에 PASSWORD_LIFE_TIME=90, PASSWORD_VERIFY_FUNCTION=ora12c_verify_function 설정함(변경 전: $life_before/$verify_before)"
    FIX_EVIDENCE="$out"
}

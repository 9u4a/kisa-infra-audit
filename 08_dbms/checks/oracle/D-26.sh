# D-26 (상) 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 감사 로그 저장 정책 수립·적용 / 취약 = 감사 로그 미저장·정책 미적용
# AUDIT_TRAIL 파라미터가 NONE 이면 감사 자체가 꺼져 있는 것이므로 명백한 취약으로 본다.
run_check() {
    out=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'audit_trail';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="audit_trail = $out"
    val=$(printf '%s' "$out" | tr -d ' \r')
    if [ -z "$val" ] || [ "$val" = "NONE" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="AUDIT_TRAIL이 NONE(감사 미사용)으로 설정되어 있음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="감사 기능은 활성화됨(AUDIT_TRAIL=$val) - 감사 범위가 기관 정책에 맞는지 수동 확인 필요"
    fi
}

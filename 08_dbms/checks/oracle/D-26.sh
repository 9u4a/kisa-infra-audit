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
        # AUDIT_TRAIL 은 기존(전통) 감사만 나타낸다. 12c 이상 Unified Auditing 정책이 켜져 있으면 감사는 동작 중이다 -
        # 예전에는 이 경우도 VULN 이었다(진단 검수 D-R11). 조회 실패면 판단하지 않고 ERROR.
        ua=$(oracle_query "SELECT COUNT(*) FROM audit_unified_enabled_policies;")
        if [ $? -ne 0 ]; then
            # ORA-00942 는 "12c 미만이라 뷰가 없음"과 "권한이 없어 안 보임"을 구분하지 못한다(Oracle 실기: SELECT_CATALOG_ROLE
            # 계정에서 942) - v$option 에 Unified Auditing 행이 아예 없을 때만 미지원 버전으로 본다.
            uaopt=$(oracle_query "SELECT COUNT(*) FROM v\$option WHERE parameter = 'Unified Auditing';" | tr -d ' \t\r' | awk 'NF' | head -n 1)
            if printf '%s' "$ua" | grep -q 'ORA-00942' && [ "$uaopt" = "0" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="AUDIT_TRAIL이 NONE(감사 미사용)으로 설정되어 있음(Unified Auditing 미지원 버전)"
            else
                CHECK_STATUS="ERROR"; CHECK_DETAIL="AUDIT_TRAIL=NONE 이나 Unified Auditing 정책을 조회하지 못함: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $ua"
            fi
            return
        fi
        ua=$(printf '%s' "$ua" | tr -d ' \t\r' | awk 'NF' | head -n 1)
        CHECK_EVIDENCE="audit_trail = $out
활성 Unified Auditing 정책 수 = $ua"
        if [ -n "$ua" ] && [ "$ua" != "0" ]; then
            CHECK_STATUS="MANUAL"; CHECK_DETAIL="전통 감사(AUDIT_TRAIL)는 NONE 이나 Unified Auditing 정책 ${ua}개가 활성화됨 - 감사 범위가 기관 정책에 맞는지 수동 확인 필요"
        else
            CHECK_STATUS="VULN"; CHECK_DETAIL="AUDIT_TRAIL이 NONE 이고 활성화된 Unified Auditing 정책도 없음(감사 미사용)"
        fi
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="감사 기능은 활성화됨(AUDIT_TRAIL=$val) - 감사 범위가 기관 정책에 맞는지 수동 확인 필요"
    fi
}

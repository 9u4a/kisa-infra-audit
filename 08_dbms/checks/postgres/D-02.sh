# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [PostgreSQL]
# 판단 기준(가이드 원문): 불필요 계정 존재 여부는 조직의 운영 정책을 알아야 판단 가능
# - 완전 자동 판정 불가. 전체 역할(role) 목록을 증적으로 제공하고 수동 확인을 안내한다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT rolname, rolcanlogin, rolvaliduntil FROM pg_roles ORDER BY rolname;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="전체 role 목록을 확인하여 불필요한(퇴직자/테스트/데모) 계정이 있는지 수동 검토 필요"
    CHECK_EVIDENCE="$out"
    # 1.7.0 값 지정 조치: D-02.accounts 후보(로그인 가능 역할, pg_ 내장 역할 제외) - lib/policy_draft.py 가 읽는다(조치가 거부하는 계정도 섞일 수 있음)
    cand=$(printf '%s\n' "$out" | awk -F'|' '$2 == "t" && index($1, "pg_") != 1 { print $1 }' | grep -v ',' | tr '\n' ',' | sed 's/,$//')
    [ -n "$cand" ] && CHECK_EVIDENCE="$CHECK_EVIDENCE

[candidates] $cand"
}

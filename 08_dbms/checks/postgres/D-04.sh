# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [PostgreSQL]
# 판단 기준(가이드 원문): "필요한 계정에만" 부여되었는지는 조직의 업무 요구를 알아야 판단
# 가능 - 완전 자동 판정 불가. superuser 권한 보유 role 목록을 증적으로 제공한다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT rolname FROM pg_roles WHERE rolsuper ORDER BY rolname;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="superuser 권한 보유 role 목록 - 관리 업무에 실제로 필요한 계정인지 수동 검토 필요"
    CHECK_EVIDENCE="$out"
    # 1.7.0 값 지정 조치: D-04.accounts 후보(SUPERUSER 역할) - lib/policy_draft.py 가 읽는다(조치가 거부하는 계정도 섞일 수 있음)
    cand=$(printf '%s\n' "$out" | awk 'NF { print $1 }' | grep -v ',' | tr '\n' ',' | sed 's/,$//')
    [ -n "$cand" ] && CHECK_EVIDENCE="$CHECK_EVIDENCE

[candidates] $cand"
}

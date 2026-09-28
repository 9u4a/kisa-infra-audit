# D-10 (상) 원격에서 DB 서버로의 접속 제한 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 지정된 IP에서만 접근 가능하도록 제한 / 취약 = 제한 없음
# pg_hba.conf 에서 host 타입 행 중 CIDR 이 0.0.0.0/0 · ::/0 · all(전체 허용)인 행이 있으면 취약.
# 주석(#)/빈 줄은 먼저 제거한 뒤 검사한다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    hba=$(postgres_hba_path)
    if [ -z "$hba" ] || [ ! -f "$hba" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="pg_hba.conf 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    active=$(grep -Ev '^[[:space:]]*(#|$)' "$hba")
    open=$(printf '%s\n' "$active" | grep -E '^host' | grep -E '0\.0\.0\.0/0|::/0|[[:space:]]all[[:space:]]')
    CHECK_EVIDENCE="[$hba]
$active"
    if [ -n "$open" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="pg_hba.conf 에 모든 IP를 허용하는 host 규칙이 존재함: $open"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="pg_hba.conf 에 전체 허용(0.0.0.0/0 등) host 규칙이 없음"
    fi
}

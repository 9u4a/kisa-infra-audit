# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [PostgreSQL]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 완전 자동 판정 불가. PostgreSQL은
# 비밀번호 복잡도를 강제하는 기본 메커니즘이 없어(passwordcheck 확장 필요) 확장 설치 여부와
# 로그인 가능한 role 중 만료일(rolvaliduntil) 미설정 계정 목록을 증적으로 제공한다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    ext=$(psql_query "SELECT extname FROM pg_extension WHERE extname='passwordcheck';")
    rc=$?
    novalid=$(psql_query "SELECT rolname FROM pg_roles WHERE rolcanlogin AND rolvaliduntil IS NULL ORDER BY rolname;")
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE=""
        return
    fi
    CHECK_EVIDENCE="[passwordcheck 확장 설치 여부] ${ext:-미설치}
[비밀번호 만료일(rolvaliduntil) 미설정 로그인 계정]
$novalid"
    if [ -z "$ext" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 복잡도 검증 확장(passwordcheck)이 설치되어 있지 않음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="passwordcheck 확장은 설치됨 - 정책 값이 기관 기준에 맞는지, 만료일 미설정 계정은 정책상 의도된 것인지 수동 확인 필요"
    fi
}

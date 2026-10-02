# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [PostgreSQL]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 완전 자동 판정 불가. PostgreSQL은
# 비밀번호 복잡도를 강제하는 기본 메커니즘이 없어(passwordcheck 모듈 필요) 모듈 로드 여부와
# 로그인 가능한 role 중 만료일(rolvaliduntil) 미설정 계정 목록을 증적으로 제공한다.
# 주의(Docker 실기 테스트로 발견한 버그): passwordcheck 는 SQL 함수가 없는 순수 C 훅 모듈이라
# .control 파일이 없고 CREATE EXTENSION/pg_extension 으로는 설치할 수도 확인할 수도 없다(공식
# postgres:16 이미지에 .so 파일은 있지만 .control 이 없어 CREATE EXTENSION 시도가 "extension은
# 사용할 수 없음" 오류로 실패함을 확인). shared_preload_libraries GUC 에 포함되어 있는지로
# 판정해야 한다(postgresql.conf 설정 + 서버 재시작 필요한 postmaster-context 파라미터).
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    preload=$(psql_query "SHOW shared_preload_libraries;")
    rc=$?
    novalid=$(psql_query "SELECT rolname FROM pg_roles WHERE rolcanlogin AND rolvaliduntil IS NULL ORDER BY rolname;")
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE=""
        return
    fi
    CHECK_EVIDENCE="[shared_preload_libraries] ${preload:-(비어있음)}
[비밀번호 만료일(rolvaliduntil) 미설정 로그인 계정]
$novalid"
    if ! printf '%s' "$preload" | grep -q passwordcheck; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 복잡도 검증 모듈(passwordcheck)이 shared_preload_libraries 에 로드되어 있지 않음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="passwordcheck 모듈은 로드되어 있음 - 정책 값이 기관 기준에 맞는지, 만료일 미설정 계정은 정책상 의도된 것인지 수동 확인 필요"
    fi
}

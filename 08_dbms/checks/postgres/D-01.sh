# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 기본 계정의 초기 비밀번호를 변경하거나 잠금설정한 경우
#                        취약 = 초기 비밀번호를 변경하지 않거나 잠금설정을 하지 않은 경우
# 자동화 범위: PostgreSQL은 postgres 계정에 고정 초기 비밀번호를 배포하지 않는다(설치 시 비밀번호
# 미설정=NULL 이 기본). pg_shadow.passwd IS NULL 여부가 "비밀번호 설정 여부"의 완전한 대리 지표다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT usename, CASE WHEN passwd IS NULL THEN 'EMPTY' ELSE 'SET' END FROM pg_shadow WHERE usename='postgres';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -z "$out" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="postgres 계정을 찾을 수 없음 - 수동 확인 필요"
        return
    fi
    if printf '%s\n' "$out" | grep -q "EMPTY"; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="postgres 계정에 비밀번호가 설정되어 있지 않음"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="postgres 계정에 비밀번호가 설정되어 있음"
    fi
}

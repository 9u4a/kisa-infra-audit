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
        return
    fi
    # 실무 적용 검증 P-09: 비밀번호가 있어도 pg_hba 의 trust 규칙에 걸리면 비밀번호 없이 postgres 로 접속된다 - 예전에는 보지 않고
    # GOOD 이었다. 서버가 실제로 읽은 규칙(pg_hba_file_rules, 원격 실행에서도 조회 가능)으로 확인한다.
    trust=$(psql_query "SELECT type || ' ' || array_to_string(database, ',') || ' ' || array_to_string(user_name, ',') || ' ' || coalesce(address, '(socket)') FROM pg_hba_file_rules WHERE auth_method = 'trust' AND ('all' = ANY(user_name) OR 'postgres' = ANY(user_name));")
    if [ $? -ne 0 ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="postgres 계정에 비밀번호가 설정되어 있으나 pg_hba 규칙(trust 여부)을 조회하지 못함 - 비밀번호 없이 접속되는 규칙이 없는지 수동 확인 필요"
        return
    fi
    CHECK_EVIDENCE="$out${trust:+
pg_hba trust 규칙(비밀번호 없이 접속):
$trust}"
    if [ -n "$trust" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="postgres 계정에 비밀번호는 설정되어 있으나 pg_hba trust 규칙으로 비밀번호 없이 접속할 수 있음 - 규칙의 필요성·범위 확인 필요"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="postgres 계정에 비밀번호가 설정되어 있고 trust(무인증) 접속 규칙이 없음"
    fi
}

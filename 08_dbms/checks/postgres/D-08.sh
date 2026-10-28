# D-08 (상) 안전한 암호화 알고리즘 사용 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = SHA-256 이상 해시 알고리즘 사용 / 취약 = SHA-256 미만
# PostgreSQL password_encryption 설정: scram-sha-256(양호) vs md5(취약).
# 진단 검수 D-R7: 설정이 scram 이어도 바꾸기 전에 저장된 비밀번호는 md5 해시로 남는다 - pg_authid 에서 md5 로
# 저장된 로그인 role 이 있으면 취약. pg_authid 는 superuser 만 읽을 수 있어 조회 실패는 ERROR(해시 값은 남기지 않음).
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SHOW password_encryption;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    md5roles=$(psql_query "SELECT rolname FROM pg_authid WHERE rolpassword LIKE 'md5%' ORDER BY rolname;")
    rc2=$?
    CHECK_EVIDENCE="password_encryption = $out
[md5 해시로 저장된 role]
${md5roles:-(없음)}"
    case "$out" in
        *md5*) CHECK_STATUS="VULN"; CHECK_DETAIL="SHA-256 미만의 md5 알고리즘을 사용함" ;;
        *scram-sha-256*)
            if [ $rc2 -ne 0 ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="password_encryption=scram-sha-256 이나 저장된 해시 종류(pg_authid)를 조회하지 못함(superuser 필요): $(head -1 "$DB_ERR_FILE" 2>/dev/null)"
            elif [ -n "$md5roles" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="설정은 scram-sha-256 이나 비밀번호가 md5 해시로 저장된 role 이 있음: $(printf '%s' "$md5roles" | tr '\n' ' ')"
            else
                CHECK_STATUS="GOOD"; CHECK_DETAIL="SHA-256 기반 scram-sha-256 알고리즘을 사용하고 md5 로 저장된 role 이 없음"
            fi ;;
        *) CHECK_STATUS="MANUAL"; CHECK_DETAIL="password_encryption 값을 확인할 수 없음: $out" ;;
    esac
}

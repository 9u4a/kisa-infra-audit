# D-08 (상) 안전한 암호화 알고리즘 사용 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = SHA-256 이상 해시 알고리즘 사용 / 취약 = SHA-256 미만
# PostgreSQL password_encryption 설정: scram-sha-256(양호) vs md5(취약).
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
    CHECK_EVIDENCE="password_encryption = $out"
    case "$out" in
        *scram-sha-256*) CHECK_STATUS="GOOD"; CHECK_DETAIL="SHA-256 기반 scram-sha-256 알고리즘을 사용함" ;;
        *md5*) CHECK_STATUS="VULN"; CHECK_DETAIL="SHA-256 미만의 md5 알고리즘을 사용함" ;;
        *) CHECK_STATUS="MANUAL"; CHECK_DETAIL="password_encryption 값을 확인할 수 없음: $out" ;;
    esac
}

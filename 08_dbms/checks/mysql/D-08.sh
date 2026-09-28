# D-08 (상) 안전한 암호화 알고리즘 사용 [MySQL]
# 판단 기준(가이드 원문): 양호 = SHA-256 이상 해시 알고리즘 사용 / 취약 = SHA-256 미만
# mysql_native_password 는 SHA-1 기반이라 취약, caching_sha2_password/sha256_password 는 양호.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host, plugin FROM mysql.user WHERE plugin != '';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if printf '%s\n' "$out" | grep -qwE 'mysql_native_password|mysql_old_password'; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="SHA-1 기반 mysql_native_password(또는 구버전 알고리즘)를 사용하는 계정이 존재함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="모든 계정이 SHA-256 이상 알고리즘(caching_sha2_password 등)을 사용함"
    fi
}

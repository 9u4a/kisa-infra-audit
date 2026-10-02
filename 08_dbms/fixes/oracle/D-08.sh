# D-08 (상) 안전한 암호화 알고리즘 사용 [Oracle] — 조치 [fix: confirm]
# sqlnet.ora 는 매 연결 시 새로 읽히는 설정이라 인스턴스/리스너 재시작이 필요 없다.
run_fix() {
    f=$(oracle_sqlnet_ora)
    if [ -z "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="sqlnet.ora 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$f"
    if grep -qi 'ALLOWED_LOGON_VERSION_SERVER' "$f"; then
        sed -i -E 's/^([[:space:]]*SQLNET\.ALLOWED_LOGON_VERSION_SERVER[[:space:]]*=).*/\1 12/I' "$f"
    else
        printf '\nSQLNET.ALLOWED_LOGON_VERSION_SERVER=12\n' >> "$f"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$f 에 SQLNET.ALLOWED_LOGON_VERSION_SERVER=12 설정함(SHA-512 미만 인증 버전 거부)"
    FIX_EVIDENCE="$(grep -i ALLOWED_LOGON_VERSION_SERVER "$f")"
}

# U-13 (중) 안전한 비밀번호 암호화 알고리즘 사용 — 조치
# 가이드 조치 방법: 해시 알고리즘을 SHA-2 이상(SHA-512 등)으로 설정
# 자동화 범위: login.defs ENCRYPT_METHOD 를 SHA512 로 설정한다. 이미 저장된 기존 비밀번호
# 해시는 재변경 전까지 유지되므로(신규/변경되는 비밀번호부터 적용) 기존 계정에는 영향 없다.
run_fix() {
    logindefs="/etc/login.defs"
    if [ ! -f "$logindefs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$logindefs 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$logindefs"
    if grep -qE '^[[:space:]]*ENCRYPT_METHOD' "$logindefs"; then
        sed -i -E 's/^[[:space:]]*ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' "$logindefs"
    else
        printf 'ENCRYPT_METHOD SHA512\n' >> "$logindefs"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$logindefs 에 ENCRYPT_METHOD SHA512 설정함(신규/변경 비밀번호부터 적용)"
    FIX_EVIDENCE="$(grep ENCRYPT_METHOD "$logindefs")"
}

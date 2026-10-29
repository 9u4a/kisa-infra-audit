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
    # check(U-13)가 /etc/shadow 의 기존 취약 해시도 보게 되어(진단 검수 U-R13) login.defs 만 바꿔서는 재검증을 통과할 수
    # 없다 - 비밀번호 재설정은 자동화 대상이 아니므로 바꾸지 않고 대상 계정을 안내한다.
    if [ -r /etc/shadow ]; then
        _weak=$(awk -F: '$2 !~ /^[!*]|^$/ && $2 !~ /^\$(5|6|y|gy)\$/ { printf "%s ", $1 }' /etc/shadow 2>/dev/null)
        if [ -n "$_weak" ]; then
            # 아무것도 바꾸지 않았으므로 SKIPPED(fix.sh 가 재검증·원복 없이 사유만 기록)
            FIX_STATUS="SKIPPED"
            FIX_DETAIL="취약한 해시를 쓰는 기존 계정($_weak)은 비밀번호 재설정(passwd)이 필요해 자동 조치 불가 - 변경하지 않음. $logindefs 의 ENCRYPT_METHOD SHA512 설정과 함께 수동 조치할 것"
            FIX_EVIDENCE=""
            return
        fi
    fi
    fix_backup "$logindefs"
    if grep -qE '^[[:space:]]*ENCRYPT_METHOD' "$logindefs"; then
        fix_sed_inplace "$logindefs" -E 's/^[[:space:]]*ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/'
    else
        printf 'ENCRYPT_METHOD SHA512\n' >> "$logindefs"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$logindefs 에 ENCRYPT_METHOD SHA512 설정함(신규/변경 비밀번호부터 적용)"
    FIX_EVIDENCE="$(grep ENCRYPT_METHOD "$logindefs")"
}

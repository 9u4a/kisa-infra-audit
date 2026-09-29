# U-03 (상) 계정 잠금 임계값 설정 — 조치
# 가이드 조치 방법: pam_faillock(또는 pam_tally2)/faillock.conf 의 deny 값을 10회 이하로 설정
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    faillock_conf="/etc/security/faillock.conf"
    pam_files="/etc/pam.d/system-auth /etc/pam.d/password-auth /etc/pam.d/common-auth"

    if [ -f "$faillock_conf" ]; then
        fix_backup "$faillock_conf"
        if grep -qE '^[[:space:]]*deny[[:space:]]*=' "$faillock_conf"; then
            sed -i -E 's/^[[:space:]]*deny[[:space:]]*=.*/deny = 5/' "$faillock_conf"
        else
            printf 'deny = 5\n' >> "$faillock_conf"
        fi
        FIX_STATUS="APPLIED"
        FIX_DETAIL="$faillock_conf 에 deny=5 설정함"
        FIX_EVIDENCE="$(grep -E '^[[:space:]]*deny' "$faillock_conf")"
        return
    fi

    for f in $pam_files; do
        [ -f "$f" ] || continue
        if grep -qE 'pam_(faillock|tally2?)\.so.*deny=' "$f"; then
            fix_backup "$f"
            sed -i -E 's/(pam_(faillock|tally2?)\.so.*)deny=[0-9]+/\1deny=5/' "$f"
            FIX_STATUS="APPLIED"
            FIX_DETAIL="$f 의 pam_faillock/tally2 deny 값을 5로 설정함"
            FIX_EVIDENCE="$(grep -E 'pam_(faillock|tally2?)\.so' "$f")"
            return
        fi
    done

    FIX_STATUS="ERROR"
    FIX_DETAIL="faillock.conf 및 PAM 설정에서 계정 잠금 메커니즘을 찾지 못해 자동 조치 불가 (PAM 모듈 구성을 수동 확인 필요)"
    FIX_EVIDENCE=""
}

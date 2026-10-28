# U-03 (상) 계정 잠금 임계값 설정 — 조치
# 가이드 조치 방법: pam_faillock(또는 pam_tally2)/faillock.conf 의 deny 값을 10회 이하로 설정
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    faillock_conf="/etc/security/faillock.conf"
    pam_files="/etc/pam.d/system-auth /etc/pam.d/password-auth /etc/pam.d/common-auth"

    # check(U-03)와 같은 기준: 주석이 아닌 PAM 줄에 모듈이 있어야 faillock.conf/deny= 가 의미 있다(진단 검수 U-R4).
    # 모듈이 없는데 faillock.conf 만 고치면 재검증이 실패하므로 PAM 스택 구성은 수동 조치로 안내한다.
    _pam_active=0
    for f in $pam_files; do
        [ -f "$f" ] || continue
        grep -vE '^[[:space:]]*#' "$f" 2>/dev/null | grep -qE 'pam_(faillock|tally2?)\.so' && _pam_active=1
    done
    if [ "$_pam_active" -eq 0 ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="PAM 스택에 pam_faillock/pam_tally 모듈이 없어 자동 조치 불가 (authselect/pam-auth-update 등으로 PAM 모듈 구성을 수동 적용 필요)"
        FIX_EVIDENCE=""
        return
    fi

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
        if grep -vE '^[[:space:]]*#' "$f" | grep -qE 'pam_(faillock|tally2?)\.so.*deny='; then
            fix_backup "$f"
            sed -i -E '/^[[:space:]]*#/!s/(pam_(faillock|tally2?)\.so.*)deny=[0-9]+/\1deny=5/' "$f"
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

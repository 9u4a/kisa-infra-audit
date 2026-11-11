# U-03 (상) 계정 잠금 임계값 설정 — 조치
# 변경: /etc/security/faillock.conf deny = 5 (있으면 교체, 없으면 추가), 파일 없으면 PAM(system-auth/password-auth/common-auth) pam_faillock/tally deny=5. rhel 계열에서 PAM 이 authselect 관리(프로필 선택·미수정)인데 pam_faillock 이 없으면 authselect enable-feature with-faillock 을 먼저 적용(/etc/authselect·/var/lib/authselect 백업). 그 밖에 PAM 모듈 미구성 시 변경 안 함(authselect 미관리 PAM 은 수동)
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
    # G-07: Rocky/RHEL 9 기본(authselect minimal/sssd 프로필)은 pam_faillock 이 꺼져 있어 늘 "자동 조치 불가"였다(실 VM 확인).
    # PAM 이 authselect 관리이고 프로필 파일이 수정되지 않았으면(authselect check) 가이드 조치(pam_faillock 사용)를 authselect 로 켠다.
    # /etc/pam.d/system-auth 등은 심볼릭 링크라 링크가 아니라 링크 대상(실제 파일)을 백업한다.
    _authselect_note=""
    if [ "$_pam_active" -eq 0 ] && [ "$OS_FAMILY" = "rhel" ] && command -v authselect >/dev/null 2>&1 \
        && authselect current >/dev/null 2>&1 && authselect check >/dev/null 2>&1; then
        # RHEL 9 는 생성 파일을 /var/lib/authselect 에 두고 /etc/authselect·/etc/pam.d 에서 링크한다(Docker rhel 케이스 실측) - 두 곳 모두
        for f in /etc/authselect/* /var/lib/authselect/*; do
            [ -f "$f" ] && [ ! -h "$f" ] && fix_backup "$f"
        done
        if _out=$(authselect enable-feature with-faillock 2>&1); then
            for f in $pam_files; do
                [ -f "$f" ] || continue
                grep -vE '^[[:space:]]*#' "$f" 2>/dev/null | grep -qE 'pam_faillock\.so' && _pam_active=1
            done
            _authselect_note="authselect enable-feature with-faillock 적용; "
        fi
        if [ "$_pam_active" -eq 0 ]; then
            FIX_STATUS="ERROR"
            FIX_DETAIL="authselect enable-feature with-faillock 이 실패했거나 PAM 에 pam_faillock 이 생기지 않음: $(printf '%s' "$_out" | head -n 3)"
            FIX_EVIDENCE="$(authselect current 2>&1)"
            return
        fi
    fi
    if [ "$_pam_active" -eq 0 ]; then
        FIX_STATUS="ERROR"
        # authselect 가 PAM 을 관리하지 않는 rhel(G-07 Rocky 9 kickstart 최소 설치: "기존 구성이 없습니다")은 프로필 선택이
        # PAM·nsswitch 전체를 바꾸고(--force), PAM 파일 직접 편집은 로그인 차단 위험이 있어 자동으로 하지 않는다
        _hint="authselect/pam-auth-update 등으로 PAM 모듈 구성을 수동 적용 필요"
        if [ "$OS_FAMILY" = "rhel" ] && command -v authselect >/dev/null 2>&1; then
            if ! authselect current >/dev/null 2>&1; then
                _hint="PAM 이 authselect 관리가 아님 - 현재 PAM 설정을 확인한 뒤 authselect select <프로필> with-faillock --force 또는 system-auth·password-auth 에 pam_faillock 을 수동 추가"
            elif ! authselect check >/dev/null 2>&1; then
                _hint="authselect 프로필 파일이 수동으로 수정되어 있어(authselect check 실패) 자동 변경하지 않음 - 수정 내용을 확인한 뒤 authselect enable-feature with-faillock 수동 적용"
            fi
        fi
        FIX_DETAIL="PAM 스택에 pam_faillock/pam_tally 모듈이 없어 자동 조치 불가 ($_hint)"
        FIX_EVIDENCE=""
        return
    fi

    if [ -f "$faillock_conf" ]; then
        fix_backup "$faillock_conf"
        if grep -qE '^[[:space:]]*deny[[:space:]]*=' "$faillock_conf"; then
            fix_sed_inplace "$faillock_conf" -E 's/^[[:space:]]*deny[[:space:]]*=.*/deny = 5/'
        else
            printf 'deny = 5\n' >> "$faillock_conf"
        fi
        FIX_STATUS="APPLIED"
        FIX_DETAIL="${_authselect_note}$faillock_conf 에 deny=5 설정함"
        FIX_EVIDENCE="$(grep -E '^[[:space:]]*deny' "$faillock_conf")"
        return
    fi

    for f in $pam_files; do
        [ -f "$f" ] || continue
        if grep -vE '^[[:space:]]*#' "$f" | grep -qE 'pam_(faillock|tally2?)\.so.*deny='; then
            fix_backup "$f"
            fix_sed_inplace "$f" -E '/^[[:space:]]*#/!s/(pam_(faillock|tally2?)\.so.*)deny=[0-9]+/\1deny=5/'
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

# U-06 (상) 사용자 계정 su 기능 제한 — 조치
# 가이드 조치 방법: /etc/pam.d/su 에 pam_wheel.so 활성화(wheel 그룹만 su 허용)
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    pam_su="/etc/pam.d/su"
    if [ ! -f "$pam_su" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$pam_su 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$pam_su"
    if grep -qE '^[[:space:]]*#[[:space:]]*auth[[:space:]]+(required|requisite|sufficient)[[:space:]]+pam_wheel\.so' "$pam_su"; then
        sed -i -E 's/^[[:space:]]*#[[:space:]]*(auth[[:space:]]+(required|requisite|sufficient)[[:space:]]+pam_wheel\.so.*)/\1/' "$pam_su"
    else
        printf 'auth\t\trequired\tpam_wheel.so use_uid\n' >> "$pam_su"
    fi
    getent group wheel >/dev/null 2>&1 || groupadd wheel 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$pam_su 에 pam_wheel.so 를 활성화함(wheel 그룹 계정만 su 허용)"
    FIX_EVIDENCE="$(grep pam_wheel "$pam_su")"
}

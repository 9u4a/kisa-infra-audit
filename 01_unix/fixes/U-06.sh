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
    # wheel 그룹에 root 외 구성원이 없으면 su 를 막는 순간 아무도 su 로 root 가 될 수 없다(예전에는 빈 wheel
    # 그룹을 만들어 그대로 적용했다 - Debian 계열은 wheel 이 기본으로 없어 관리자가 su 를 못 쓰게 됐다).
    # 구성원 = /etc/group 4번째 필드 + 기본 그룹(gid)이 wheel 인 계정.
    wheel_gid=$(awk -F: '$1 == "wheel" { print $3 }' /etc/group 2>/dev/null)
    members=""
    if [ -n "$wheel_gid" ]; then
        members=$( { awk -F: '$1 == "wheel" { print $4 }' /etc/group | tr ',' '\n'
                     awk -F: -v g="$wheel_gid" '$4 == g { print $1 }' /etc/passwd; } | grep -v '^root$' | grep -v '^$' | sort -u | tr '\n' ' ')
    fi
    if [ -z "$members" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="wheel 그룹이 없거나 root 외 구성원이 없어 변경하지 않음 - su 를 wheel 로 제한하면 관리자가 su 를 쓸 수 없게 됨. 관리 계정을 wheel 그룹에 추가(usermod -aG wheel <계정>)한 뒤 다시 실행할 것"
        FIX_EVIDENCE=""
        return
    fi
    note=""
    if [ -n "${SUDO_USER:-}" ] && ! printf ' %s ' "$members" | grep -q " $SUDO_USER "; then
        note=" / 주의: 지금 실행한 관리자($SUDO_USER)는 wheel 구성원이 아니어서 su 는 쓸 수 없음(sudo 는 영향 없음)"
    fi

    fix_backup "$pam_su"
    # check(U-06)와 같은 기준(진단 검수 U-R8): 제한이 되는 줄은 required/requisite + deny 없음. 예전에는 주석 처리된
    # pam_wheel 줄을 전부 풀어 Debian 기본 예시의 "sufficient pam_wheel.so trust"(wheel 무암호 su)·"deny group=nosu"
    # 까지 활성화했다 - 인자 없는(또는 use_uid 만 있는) required 예시 줄 하나만 푼다.
    if grep -qE '^[[:space:]]*#[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_wheel\.so([[:space:]]+use_uid)?[[:space:]]*$' "$pam_su"; then
        sed -i -E '0,/^[[:space:]]*#[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_wheel\.so([[:space:]]+use_uid)?[[:space:]]*$/s//auth required pam_wheel.so\1/' "$pam_su"
    else
        printf 'auth\t\trequired\tpam_wheel.so use_uid\n' >> "$pam_su"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$pam_su 에 pam_wheel.so 를 활성화함(wheel 그룹 계정만 su 허용, wheel 구성원: $members)$note"
    FIX_EVIDENCE="$(grep pam_wheel "$pam_su")"
}

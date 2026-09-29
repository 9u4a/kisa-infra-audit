# U-01 (상) root 계정 원격 접속 제한 — 조치
# 가이드 조치 방법: sshd_config 에 PermitRootLogin no 설정
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    sshd_cfg="/etc/ssh/sshd_config"
    if [ ! -f "$sshd_cfg" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$sshd_cfg 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$sshd_cfg"
    if grep -qiE '^[[:space:]]*PermitRootLogin[[:space:]]' "$sshd_cfg"; then
        sed -i -E 's/^[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin no/I' "$sshd_cfg"
    else
        printf '\nPermitRootLogin no\n' >> "$sshd_cfg"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$sshd_cfg 에 PermitRootLogin no 설정함 (sshd 재시작/reload 후 적용됨 — 현재 세션에는 영향 없음)"
    FIX_EVIDENCE="$(grep -i PermitRootLogin "$sshd_cfg")"
}

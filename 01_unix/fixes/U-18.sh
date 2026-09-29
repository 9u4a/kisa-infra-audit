# U-18 (상) /etc/shadow 파일 소유자 및 권한 설정 — 조치
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris) fix_set_owner_perm "/etc/shadow" "root" 400 ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE="" ;;
    esac
}

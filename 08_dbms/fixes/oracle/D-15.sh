# D-15 (하) 관리자 이외의 사용자가 리스너 로그/trace 파일 변경 제한 [Oracle] — 조치 [fix: auto]
# checks/oracle/D-15.sh: 양호 = listener.ora 권한 644 이하 & ADMIN_RESTRICTIONS_LISTENER=ON.
run_fix() {
    f=$(oracle_listener_ora)
    if [ -z "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="listener.ora 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    perm=$(stat -L -c '%a' "$f" 2>/dev/null)
    if [ -z "$perm" ] || [ "$perm" -gt 644 ] 2>/dev/null; then
        owner=$(stat -L -c '%U' "$f" 2>/dev/null)
        case "$owner" in
            root|oracle) : ;;
            *) owner="oracle" ;;
        esac
        fix_set_owner_perm "$f" "$owner" 644
    fi

    if ! grep -qi 'ADMIN_RESTRICTIONS_' "$f"; then
        fix_backup "$f"
        printf '\nADMIN_RESTRICTIONS_LISTENER = ON\n' >> "$f"
    fi

    reloaded=0
    if command -v lsnrctl >/dev/null 2>&1; then
        lsnrctl reload >/dev/null 2>&1 && reloaded=1
    fi

    FIX_STATUS="APPLIED"
    FIX_DETAIL="listener.ora 권한을 644로 설정하고 ADMIN_RESTRICTIONS_LISTENER=ON 을 추가함$([ "$reloaded" -eq 1 ] && echo ' - lsnrctl reload 로 즉시 반영함' || echo ' - lsnrctl 을 찾지 못해 수동 reload 필요')"
    FIX_EVIDENCE="$(grep -i ADMIN_RESTRICTIONS_ "$f")"
}

# U-04 (상) 비밀번호 파일 보호 — 조치
# 가이드 조치 방법: pwconv 로 쉐도우 비밀번호 체계로 전환
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    if ! command -v pwconv >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="pwconv 명령을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup /etc/passwd
    [ -f /etc/shadow ] && fix_backup /etc/shadow
    _err=$(mktemp 2>/dev/null || echo "/tmp/.u04_err.$$")
    if pwconv 2>"$_err"; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="pwconv 실행으로 쉐도우 비밀번호 체계로 전환함"
        FIX_EVIDENCE="pwconv (exit 0)"
    else
        FIX_STATUS="FAILED"
        FIX_DETAIL="pwconv 실행 실패: $(cat "$_err" 2>/dev/null)"
        FIX_EVIDENCE=""
    fi
    rm -f "$_err"
}

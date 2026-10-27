# U-67 (중) 로그 디렉터리 소유자 및 권한 설정 — 조치
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    log_dir="/var/log"
    bad=$(find "$log_dir" -maxdepth 1 -type f \( ! -user root -o -perm -0133 \) 2>/dev/null | head -n 30)
    if [ -z "$bad" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 로그 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        fix_backup "$f"
        chown root "$f" 2>/dev/null
        chmod 644 "$f" 2>/dev/null
    done <<EOF
$bad
EOF
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$log_dir 내 로그 파일을 root 소유·644 권한으로 설정함(최대 30건)"
    FIX_EVIDENCE="$bad"
}

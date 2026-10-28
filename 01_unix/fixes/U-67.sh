# U-67 (중) 로그 디렉터리 소유자 및 권한 설정 — 조치
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    log_dir="/var/log"
    # check(U-67)와 같은 기준(진단 검수 U-R11): 하위 디렉터리 포함, 0133·특수비트 중 하나라도 있으면 대상.
    # 예전 -perm -0133 은 "전부 있을 때"만 맞아 664 등을 놓쳤다.
    bad=$(find "$log_dir" -type f \( ! -user root -o -perm -0100 -o -perm -0020 -o -perm -0010 -o -perm -0002 -o -perm -0001 -o -perm -4000 -o -perm -2000 -o -perm -1000 \) 2>/dev/null | head -n 200)
    if [ -z "$bad" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 로그 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        fix_backup "$f"
        chown root "$f" 2>/dev/null
        # 644 로 덮어쓰면 640/600 파일에 읽기 권한을 넓히게 되므로 644 를 넘는 비트만 뺀다.
        chmod u-xs,g-wxs,o-wx "$f" 2>/dev/null
        chmod -t "$f" 2>/dev/null
    done <<EOF
$bad
EOF
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$log_dir 내 로그 파일(하위 포함, 최대 200건)을 root 소유·644 이하 권한으로 설정함"
    FIX_EVIDENCE="$bad"
}

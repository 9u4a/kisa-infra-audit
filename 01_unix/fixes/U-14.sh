# U-14 (상) root 홈, 패스 디렉터리 권한 및 패스 설정 — 조치
# 가이드 조치 방법: PATH 맨 앞/중간의 "."(현재 디렉터리) 제거
# 자동화 범위: root 쉘 시작 파일의 PATH= 라인에서 맨 앞/중간의 "."/빈 항목만 제거한다
# (맨 뒤의 "."은 가이드상 허용되므로 건드리지 않음).
run_fix() {
    applied=""
    for f in /root/.bash_profile /root/.bashrc /root/.profile /etc/profile; do
        [ -f "$f" ] || continue
        line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?PATH=' "$f" 2>/dev/null | tail -n1)
        [ -z "$line" ] && continue
        case "$line" in
            *:.:*|*=.:*)
                fix_backup "$f"
                sed -i -E '/^[[:space:]]*(export[[:space:]]+)?PATH=/ { s/(:)\.(:)/\1\2/g; s/(=)\.:/\1/; }' "$f"
                applied="$applied $f"
                ;;
        esac
    done
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="root 쉘 시작 파일에서 조치가 필요한 PATH 설정을 찾지 못함(현재 프로세스 PATH만 취약했을 수 있음 - 재로그인 후 재확인 필요)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="PATH 에서 맨 앞/중간의 '.'(현재 디렉터리)를 제거함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

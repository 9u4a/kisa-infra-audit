# U-63 (중) sudo 명령어 접근 관리 — 조치
# 변경: /etc/sudoers 소유자 root·권한 440 으로 설정(파일 없으면 NA)
run_fix() {
    if [ ! -e /etc/sudoers ]; then
        FIX_STATUS="NA"; FIX_DETAIL="/etc/sudoers 파일이 없어 조치 대상 없음(sudo 미사용)"; FIX_EVIDENCE=""
        return
    fi
    fix_set_owner_perm "/etc/sudoers" "root" 440
}

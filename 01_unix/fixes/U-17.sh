# U-17 (상) 시스템 시작 스크립트 권한 설정 — 조치
# 가이드 조치 방법: 시작 스크립트(유닛 파일)를 root 소유로, 그룹/기타 쓰기 권한 제거
run_fix() {
    systemd_dir="/etc/systemd/system"
    if [ ! -d "$systemd_dir" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="레거시 init 시스템은 자동 조치 미구현(수동 확인 필요)"; FIX_EVIDENCE=""
        return
    fi
    _list=$(find -L "$systemd_dir" -maxdepth 2 -type f \( ! -user root -o -perm -0022 \) 2>/dev/null | head -n 50)
    if [ -z "$_list" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 유닛 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    printf '%s\n' "$_list" | while IFS= read -r _f; do
        [ -z "$_f" ] && continue
        fix_backup "$_f"
        chown root "$_f" 2>/dev/null
        chmod go-w "$_f" 2>/dev/null
    done
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$systemd_dir 하위 유닛 파일을 root 소유로, 그룹/기타 쓰기 권한을 제거함"
    FIX_EVIDENCE="$_list"
}

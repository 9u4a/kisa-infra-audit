# U-20 (상) /etc/(x)inetd.conf 파일 소유자 및 권한 설정 — 조치
run_fix() {
    if [ -f /etc/xinetd.conf ]; then
        fix_set_owner_perm "/etc/xinetd.conf" "root" 600
        _base_detail=$FIX_DETAIL
        if [ -d /etc/xinetd.d ]; then
            for f in /etc/xinetd.d/*; do
                [ -f "$f" ] || continue
                chown root "$f" 2>/dev/null
                chmod go-w "$f" 2>/dev/null
            done
            FIX_DETAIL="$_base_detail / /etc/xinetd.d 내 파일의 소유자를 root로, 그룹/기타 쓰기 권한을 제거함"
        fi
        return
    fi
    if [ -f /etc/inetd.conf ]; then
        fix_set_owner_perm "/etc/inetd.conf" "root" 600
        return
    fi
    if [ -f /etc/systemd/system.conf ]; then
        fix_set_owner_perm "/etc/systemd/system.conf" "root" 600
        return
    fi
    FIX_STATUS="NA"; FIX_DETAIL="(x)inetd 및 systemd 설정 파일 모두 존재하지 않아 조치 대상 없음"; FIX_EVIDENCE=""
}

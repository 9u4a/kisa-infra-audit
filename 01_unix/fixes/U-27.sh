# U-27 (상) $HOME/.rhosts, hosts.equiv 사용 금지 — 조치
# 가이드 조치 방법: 소유자/권한(600 이하)을 바로잡고 "+"(모든 호스트 신뢰) 설정 제거
run_fix() {
    applied=""
    fix_one() {
        _f=$1
        [ -f "$_f" ] || return
        fix_backup "$_f"
        sed -i '/^[[:space:]]*+/d' "$_f"
        chmod 600 "$_f" 2>/dev/null
        applied="$applied $_f"
    }
    fix_one /etc/hosts.equiv
    passwd_file="/etc/passwd"
    if [ -r "$passwd_file" ]; then
        homes=$(awk -F: '{print $6}' "$passwd_file" | sort -u)
        for h in $homes; do
            fix_one "$h/.rhosts"
        done
    fi
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="hosts.equiv/.rhosts 파일이 없어 조치 대상 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="'+' 설정 제거 및 권한을 600으로 설정함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

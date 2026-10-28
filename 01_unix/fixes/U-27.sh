# U-27 (상) $HOME/.rhosts, hosts.equiv 사용 금지 — 조치
# 가이드 조치 방법: 소유자/권한(600 이하)을 바로잡고 "+"(모든 호스트 신뢰) 설정 제거
run_fix() {
    applied=""
    # check(U-27)와 같은 기준(진단 검수 U-R14): 소유자(hosts.equiv=root, .rhosts=해당 계정), 어느 필드든 "+" 인 줄,
    # 원격·자동마운트 홈은 건드리지 않음.
    fix_one() {
        _f=$1; _own=$2
        [ -f "$_f" ] || return
        fix_backup "$_f"
        _tmp="$_f.kisa.$$"
        awk '$0 ~ /^[[:space:]]*#/ { print; next } { hit = ($1 ~ /^\+/); for (i = 2; i <= NF; i++) if ($i == "+") hit = 1; if (!hit) print }' "$_f" > "$_tmp" \
            && cat "$_tmp" > "$_f"
        rm -f "$_tmp"
        chown "$_own" "$_f" 2>/dev/null
        chmod 600 "$_f" 2>/dev/null
        applied="$applied $_f"
    }
    fix_one /etc/hosts.equiv root
    passwd_file="/etc/passwd"
    if [ -r "$passwd_file" ]; then
        while IFS=: read -r u _ _ _ _ h _; do
            [ -n "$h" ] || continue
            is_remote_or_auto_fs "$h" && continue
            # 이미 root 소유면 그대로 둔다(check 는 root 또는 해당 계정을 허용)
            _o=$(stat -L -c '%U' "$h/.rhosts" 2>/dev/null)
            [ "$_o" = "root" ] && _o=root || _o=$u
            fix_one "$h/.rhosts" "$_o"
        done <<EOF
$(awk -F: '!seen[$1]++ { print }' "$passwd_file")
EOF
    fi
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="hosts.equiv/.rhosts 파일이 없어 조치 대상 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="'+' 설정 제거 및 권한을 600으로 설정함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

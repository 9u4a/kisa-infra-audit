# U-30 (중) UMASK 설정 관리 — 조치
# 가이드 조치 방법: UMASK 값을 022 이상으로 설정
# check(U-30)와 같은 순서·기준(진단 검수 U-R15): login.defs → /etc/profile → profile.d → bashrc 중 umask 줄이 있는
# 파일에서 022 비트를 마스킹하지 않는 값만 022 로 바꾸고(이미 027 등 더 엄격한 값은 그대로), login.defs·/etc/profile
# 에 umask 줄이 없으면 022 를 추가한다.
run_fix() {
    applied=""
    for f in /etc/login.defs /etc/profile /etc/profile.d/*.sh /etc/bashrc /etc/bash.bashrc; do
        [ -f "$f" ] || continue
        _weak=0
        for _v in $(grep -iE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f" | sed -E 's/^[[:space:]]*[Uu][Mm][Aa][Ss][Kk][[:space:]]+([0-7]+).*/\1/'); do
            [ $(( 0$_v & 022 )) -eq $(( 022 )) ] || _weak=1
        done
        _has=0; grep -qiE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f" && _has=1
        if [ "$_weak" -eq 1 ]; then
            fix_backup "$f"
            _new="umask 022"; [ "$f" = /etc/login.defs ] && _new="UMASK 022"
            # 022 비트가 빠진 값만 치환(awk: 줄 단위 판정)
            _tmp="$f.kisa.$$"
            awk -v n="$_new" '{ if (match($0, /^[[:space:]]*[Uu][Mm][Aa][Ss][Kk][[:space:]]+[0-7]+/)) { v = $2; d = 0
                for (i = 1; i <= length(v); i++) d = d * 8 + substr(v, i, 1)
                if (int(d / 16) % 2 == 0 || int(d / 2) % 2 == 0) { ind = $0; sub(/[^[:space:]].*$/, "", ind); print ind n; next } }
                print }' "$f" > "$_tmp" && cat "$_tmp" > "$f"
            rm -f "$_tmp"
            applied="$applied $f"
        elif [ "$_has" -eq 0 ] && { [ "$f" = /etc/login.defs ] || [ "$f" = /etc/profile ]; }; then
            fix_backup "$f"
            if [ "$f" = /etc/login.defs ]; then printf 'UMASK 022\n' >> "$f"; else printf 'umask 022\n' >> "$f"; fi
            applied="$applied $f"
        fi
    done
    if [ -z "$applied" ] && [ ! -f /etc/profile ] && [ ! -f /etc/login.defs ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="/etc/profile, /etc/login.defs 모두 없음"; FIX_EVIDENCE=""
    elif [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="022 미만 UMASK 설정이 없어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="UMASK 022 설정함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

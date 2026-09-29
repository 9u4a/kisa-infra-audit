# U-11 (하) 사용자 shell 점검 — 조치
# 가이드 조치 방법: 로그인이 불필요한 기본 계정에 /bin/false 또는 nologin 쉘 부여
run_fix() {
    passwd_file="/etc/passwd"
    target_accounts="daemon bin sys adm listen nobody nobody4 noaccess diag operator games gopher"
    nologin=$(command -v nologin 2>/dev/null || echo /sbin/nologin)

    fix_backup "$passwd_file"
    applied=""
    for name in $target_accounts; do
        entry=$(grep "^${name}:" "$passwd_file" 2>/dev/null)
        [ -z "$entry" ] && continue
        shell=$(printf '%s' "$entry" | awk -F: '{print $NF}')
        case "$shell" in
            */nologin|/bin/false) continue ;;
        esac
        if usermod -s "$nologin" "$name" 2>/dev/null; then
            applied="$applied $name"
        fi
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 계정이 없음(이미 모두 nologin/false)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="다음 계정의 쉘을 ${nologin} 로 변경함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

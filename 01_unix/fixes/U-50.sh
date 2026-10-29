# U-50 (상) DNS ZoneTransfer 설정 — 조치
# 자동화 범위: 관리자가 허용할 대상을 알 수 없으므로 전체 허용을 "허용 없음(none)"으로
# 안전하게 좁힌다(필요 시 관리자가 실제 보조 네임서버 IP로 다시 넓혀야 함).
# check(U-50)와 같이 include 된 파일 전체를 대상으로 한다(진단 검수 U-R5) - 예전에는 Debian 에서 include 만 있는
# /etc/bind/named.conf 를 고쳐 아무것도 바뀌지 않았다. 한 줄로 된 "allow-transfer { ... any; ... };" 만 none 으로 바꾸고
# (특정 대상으로 제한된 다른 존 설정은 건드리지 않음), options 에 allow-transfer 가 없으면 options { 바로 뒤에 넣는다.
run_fix() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf /etc/bind/named.conf.options; do
        [ -f "$f" ] && { conf="$f"; break; }
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="DNS(BIND) 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    recs=$(named_conf_flatten "$conf")
    files=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "@file" { print $2 }')
    has_opt=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "options" && $2 == "allow-transfer"')
    changed=""
    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        if grep -vE '^[[:space:]]*(#|//)' "$f" | grep -qiE 'allow-transfer[[:space:]]*\{[^}]*any[[:space:]]*;'; then
            fix_backup "$f"
            fix_sed_inplace "$f" -E '/^[[:space:]]*(#|\/\/)/!s/allow-transfer[[:space:]]*\{[^}]*any[[:space:]]*;[^}]*\}[[:space:]]*;/allow-transfer { none; };/I'
            changed="$changed $f"
        fi
        if [ -z "$has_opt" ] && grep -qE '^[[:space:]]*options[[:space:]]*\{' "$f"; then
            fix_backup "$f"
            fix_sed_inplace "$f" -E '0,/^[[:space:]]*options[[:space:]]*\{/{s/^([[:space:]]*options[[:space:]]*\{)/\1\n\tallow-transfer { none; };/}'
            has_opt=1
            changed="$changed $f"
        fi
    done <<EOF
$files
EOF
    if [ -z "$changed" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동으로 고칠 수 있는 allow-transfer/options 위치를 찾지 못함(여러 줄 블록 등) - 수동 조치 필요"
        FIX_EVIDENCE="$files"
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="allow-transfer 를 none 으로 제한함(필요 시 실제 보조 네임서버 IP로 재조정 필요) — named 재시작 후 적용:$changed"
    # shellcheck disable=SC2086
    FIX_EVIDENCE="$(grep -i allow-transfer $changed 2>/dev/null)"
}

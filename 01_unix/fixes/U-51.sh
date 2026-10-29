# U-51 (중) DNS 서비스의 취약한 동적 업데이트 설정 금지 — 조치
# check(U-51)와 같이 include 된 파일 전체에서 any 를 허용하는 allow-update 를 찾는다(진단 검수 U-R5).
run_fix() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf /etc/bind/named.conf.options; do
        [ -f "$f" ] && { conf="$f"; break; }
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="DNS(BIND) 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    files=$(named_conf_flatten "$conf" | awk -F'\t' '$1 == "@file" { print $2 }')
    changed=""
    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        grep -vE '^[[:space:]]*(#|//)' "$f" | grep -qiE 'allow-update[[:space:]]*\{[^}]*any[[:space:]]*;' || continue
        fix_backup "$f"
        fix_sed_inplace "$f" -E '/^[[:space:]]*(#|\/\/)/!s/allow-update[[:space:]]*\{[^}]*any[[:space:]]*;[^}]*\}[[:space:]]*;/allow-update { none; };/I'
        changed="$changed $f"
    done <<EOF
$files
EOF
    if [ -z "$changed" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="한 줄로 된 any 허용 allow-update 를 찾지 못함(이미 제한되었거나 여러 줄 블록 - 재검증 결과 확인)"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="allow-update 를 none 으로 제한함(동적 업데이트 비활성화) — named 재시작 후 적용:$changed"
    # shellcheck disable=SC2086
    FIX_EVIDENCE="$(grep -i allow-update $changed 2>/dev/null)"
}

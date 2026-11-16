# U-12 (하) 세션 종료 시간 설정 — 조치
# 변경: /etc/profile TMOUT=600 (기존 TMOUT= 줄은 교체, 없으면 추가) + export TMOUT 줄이 없으면 추가,
#       /etc/profile.d/*.sh 의 TMOUT=0 또는 600 초과 값은 600 으로 교체(600 이하 값은 그대로)
# 가이드 조치 방법: TMOUT 을 600초(10분) 이하로 설정

# check(U-12)와 같은 TMOUT 대입 줄 형태 - 따옴표·export/readonly/typeset/declare 가 붙은 형태 포함(진단 검수 U-R7)
U12_TMOUT_RE='^[[:space:]]*((export|readonly|typeset|declare)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+)?TMOUT=["'"'"']?[0-9]+'

run_fix() {
    f="/etc/profile"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    # V-R9: check 는 /etc/profile → /etc/profile.d/*.sh 순으로 마지막 값을 쓰므로, profile.d 에 TMOUT=0 같은 값이 남아 있으면
    # /etc/profile 만 고쳐서는 재검증이 VULN 이다. 고칠 profile.d 파일을 먼저 모두 정하고 백업한 뒤(F1) 바꾼다.
    pd_files=""
    for p in /etc/profile.d/*.sh; do
        [ -f "$p" ] || continue
        [ -n "$(u12_bad_lines "$p")" ] && pd_files="$pd_files $p"
    done
    fix_backup "$f"
    for p in $pd_files; do fix_backup "$p"; done

    if grep -qE "$U12_TMOUT_RE" "$f"; then
        fix_sed_inplace "$f" -E 's/^[[:space:]]*((export|readonly|typeset|declare)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+)?TMOUT=["'"'"']?[0-9]+.*/TMOUT=600/'
    else
        printf 'TMOUT=600\n' >> "$f"
    fi
    grep -qE '^[[:space:]]*export[[:space:]]+TMOUT([[:space:]]|$)' "$f" || printf 'export TMOUT\n' >> "$f"

    # profile.d 는 기준을 벗어난 줄의 숫자만 600 으로 바꾼다 - export·readonly·따옴표는 그대로 두고, 600 이하로 더 엄격하게
    # 정한 값은 건드리지 않는다.
    pd_ev=""
    for p in $pd_files; do
        expr=""
        for n in $(u12_bad_lines "$p"); do
            expr="$expr${n}s/(TMOUT=[\"']?)[0-9]+/\\1600/;"
        done
        fix_sed_inplace "$p" -E "$expr"
        pd_ev="$pd_ev
$p: $(grep -E "$U12_TMOUT_RE" "$p" | tr '\n' ' ')"
    done

    FIX_STATUS="APPLIED"
    if [ -n "$pd_files" ]; then
        FIX_DETAIL="$f 에 TMOUT=600(10분) 설정 및 export 처리, profile.d 의 기준 초과 TMOUT 을 600 으로 교체함:$pd_files"
    else
        FIX_DETAIL="$f 에 TMOUT=600(10분) 설정 및 export 처리함"
    fi
    FIX_EVIDENCE="$f: $(grep TMOUT "$f" | tr '\n' ' ')$pd_ev"
}

# u12_bad_lines <파일> — TMOUT 대입 값이 0 이거나 600 초과인 줄 번호(공백 구분)
u12_bad_lines() {
    grep -nE "$U12_TMOUT_RE" "$1" 2>/dev/null | while IFS= read -r l; do
        n=${l%%:*}
        v=$(printf '%s' "$l" | sed -nE 's/.*TMOUT=["'"'"']?([0-9]+).*/\1/p')
        [ -n "$v" ] || continue
        if [ "$v" -eq 0 ] || [ "$v" -gt 600 ]; then printf '%s ' "$n"; fi
    done
}

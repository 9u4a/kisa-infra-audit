# U-60 (중) SNMP Community String 복잡성 설정 — 조치
# 자동화 범위: 기본값(public/private) 또는 길이/복잡도 미달 Community String 을 임의 생성한
# 강력한 문자열로 교체한다(영문 대소문자+숫자 16자, /dev/urandom 기반).
# check(U-60)와 같이 IPv6 지시어(*6)와 includeFile/includeDir 로 불러온 파일까지 대상으로 한다(F-R8).
# 같은 문자열은 모든 파일에서 같은 새 문자열로 바꾼다(모니터링 측 갱신을 한 번에 할 수 있도록). 교체는
# community 필드(com2sec 4번째·-Cn 이면 6번째, r[ow]community 2번째)만 한다 - 예전에는 파일 전체에서 단어
# 치환(sed \b)을 해 view 이름·sysContact 등 같은 단어가 들어간 다른 줄까지 바뀔 수 있었다.
run_fix() {
    conf=""
    for f in /etc/snmp/snmpd.conf /etc/net-snmp/snmp/snmpd.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="SNMP 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    files=$(snmpd_conf_files "$conf")
    unread=$(printf '%s\n' "$files" | awk -F'\t' '$1 == "!unread" { printf " %s", $2 }')
    if [ -n "$unread" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="include 된 SNMP 설정 파일을 읽지 못해 변경하지 않음(수동 확인 필요):$unread"; FIX_EVIDENCE=""
        return
    fi

    strings=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        strings="$strings
$(_u60_fields "$f")"
    done <<EOF
$files
EOF
    strings=$(printf '%s\n' "$strings" | grep -v '^$' | sort -u)
    if [ -z "$strings" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="v1/v2 Community String 설정이 없어 조치 불필요(v3 인증정보는 자동 조치 대상 아님)"; FIX_EVIDENCE=""
        return
    fi

    map=""; applied=""
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        len=${#s}
        has_alpha=0; has_digit=0; has_special=0
        case "$s" in *[A-Za-z]*) has_alpha=1 ;; esac
        case "$s" in *[0-9]*) has_digit=1 ;; esac
        case "$s" in *[!A-Za-z0-9]*) has_special=1 ;; esac
        weak=1
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$len" -ge 10 ]; then weak=0; fi
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$has_special" -eq 1 ] && [ "$len" -ge 8 ]; then weak=0; fi
        case "$s" in public|private) weak=1 ;; esac
        [ "$weak" -eq 0 ] && continue
        newstr=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16)
        # 16자 + 영문·숫자가 모두 있어야 기준 충족 - 아니면 다시 만들지 않고 고정 형식으로 보정
        case "$newstr" in *[0-9]*) : ;; *) newstr="${newstr}7" ;; esac
        case "$newstr" in *[A-Za-z]*) : ;; *) newstr="K${newstr}" ;; esac
        [ "${#newstr}" -ge 10 ] || newstr="Snmp$(date +%s)Str"
        map="$map$s	$newstr
"
        applied="$applied $(mask_secret "$s")->****(신규 16자)"
    done <<EOF
$strings
EOF

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="모든 Community String 이 이미 복잡도 기준을 충족함"; FIX_EVIDENCE=""
        return
    fi

    KISA_U60_MAP=$map; export KISA_U60_MAP
    changed_files=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # 이 파일에 교체 대상이 있을 때만 백업·수정한다
        _u60_replace "$f" > /dev/null 2>&1 || continue
        fix_backup "$f"
        if ! _u60_replace "$f" > "$f.kisa_tmp" || ! fix_write_back "$f.kisa_tmp" "$f"; then
            rm -f "$f.kisa_tmp"; unset KISA_U60_MAP
            FIX_STATUS="ERROR"; FIX_DETAIL="$f 수정 실패"; FIX_EVIDENCE=""
            return
        fi
        changed_files="$changed_files $f"
    done <<EOF
$files
EOF
    unset KISA_U60_MAP

    FIX_STATUS="APPLIED"
    FIX_DETAIL="기준 미달 Community String 을 새로 생성한 강력한 문자열로 교체함:$applied (파일:$changed_files) (snmpd 재시작 및 모니터링 시스템 측 문자열 갱신 필요)"
    FIX_EVIDENCE="$applied"
}

# _u60_fields <파일> -- 주석이 아닌 community 지시어의 community 값을 한 줄에 하나씩 출력
_u60_fields() {
    awk '{ sub(/^[ \t]+/, ""); n = split($0, a, /[ \t]+/)
           if (a[1] ~ /^com2sec6?$/) i = (a[2] == "-Cn") ? 6 : 4
           else if (a[1] ~ /^r[ow]community6?$/) i = 2
           else next
           if (i <= n && a[i] != "") print a[i] }' "$1" 2>/dev/null
}

# _u60_replace <파일> -- KISA_U60_MAP(환경변수, "옛값<TAB>새값" 줄 목록)에 따라 community 필드만 바꿔 출력.
# 바꾼 줄이 없으면 1 을 반환한다. 비밀값을 명령행 인자로 넘기지 않으려고 환경변수(ENVIRON)를 쓴다.
_u60_replace() {
    awk 'BEGIN { n = split(ENVIRON["KISA_U60_MAP"], L, "\n")
                 for (j = 1; j <= n; j++) { t = index(L[j], "\t"); if (t > 1) m[substr(L[j], 1, t - 1)] = substr(L[j], t + 1) }
                 ch = 0 }
         { lead = $0; sub(/[^ \t].*$/, "", lead); body = $0; sub(/^[ \t]+/, "", body)
           nf = split(body, a, /[ \t]+/)
           if (a[1] ~ /^com2sec6?$/) i = (a[2] == "-Cn") ? 6 : 4
           else if (a[1] ~ /^r[ow]community6?$/) i = 2
           else { print; next }
           if (i <= nf && (a[i] in m)) {
               a[i] = m[a[i]]; out = a[1]
               for (j = 2; j <= nf; j++) out = out " " a[j]
               print lead out; ch++; next
           }
           print }
         END { exit(ch ? 0 : 1) }' "$1"
}

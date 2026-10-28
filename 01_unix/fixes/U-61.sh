# U-61 (상) SNMP Access Control 설정 — 조치
# 자동화 범위: 관리자가 허용할 네트워크 대역을 알 수 없으므로, 접근 제어가 없는(전체 허용)
# 항목은 원격 접근을 완전히 열어두는 것보다 안전한 localhost 로 좁힌다(필요 시
# 관리자가 실제 모니터링 서버 대역으로 재조정해야 함).
# check(U-61)와 같은 기준(소스가 default·0.0.0.0/0·::/0·any 또는 생략)으로, IPv6 지시어(com2sec6 →
# ::1, rocommunity6/rwcommunity6 → ::1)와 includeFile/includeDir 로 불러온 파일까지 고친다(F-R8 - 예전에는
# 주 파일의 IPv4 지시어만 고쳐 Debian 기본 "rocommunity6 public default" 가 남아 재검증 실패→원복됐다).
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

    done_list=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        _u61_restrict "$f" > /dev/null 2>&1 || continue
        fix_backup "$f"
        n=$(_u61_restrict "$f" 2>&1 >/dev/null)
        if ! _u61_restrict "$f" > "$f.kisa_tmp" 2>/dev/null || ! fix_write_back "$f.kisa_tmp" "$f"; then
            rm -f "$f.kisa_tmp"
            FIX_STATUS="ERROR"; FIX_DETAIL="$f 수정 실패"; FIX_EVIDENCE=""
            return
        fi
        done_list="$done_list $f(${n}줄)"
    done <<EOF
$files
EOF
    if [ -z "$done_list" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="이미 접근 제어가 설정되어 있거나 대상 라인이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="무제한(default/0.0.0.0/0/::/0/any/소스 생략) SNMP 접근을 localhost(127.0.0.1, IPv6 는 ::1)로 제한함:$done_list (원격 모니터링이 필요하면 실제 서버 IP로 재조정 필요) — snmpd 재시작 후 적용"
    # community 원문은 남기지 않는다(파일·줄 수만)
    FIX_EVIDENCE="$done_list"
}

# _u61_restrict <파일> -- 전체 허용 community 줄의 소스를 localhost 로 바꿔 stdout 으로 출력, 바꾼 줄 수는 stderr.
# 바꾼 줄이 없으면 1 을 반환한다.
#   com2sec[6] [-Cn ctx] <secname> <source> <community>  → source 를 localhost / ::1 로
#   r[ow]community[6] <community> [<source> [...]]       → source 를 127.0.0.1 / ::1 로(생략 시 추가)
_u61_restrict() {
    awk '{ lead = $0; sub(/[^ \t].*$/, "", lead); body = $0; sub(/^[ \t]+/, "", body); sub(/[ \t]+$/, "", body)
           nf = split(body, a, /[ \t]+/)
           if (a[1] ~ /^com2sec6?$/) { i = (a[2] == "-Cn") ? 5 : 3; rep = (a[1] == "com2sec6") ? "::1" : "localhost" }
           else if (a[1] ~ /^r[ow]community6?$/) { i = 3; rep = (a[1] ~ /6$/) ? "::1" : "127.0.0.1" }
           else { print; next }
           src = (i <= nf) ? a[i] : ""
           if (src == "default" || src == "0.0.0.0/0" || src == "::/0" || src == "any" || src == "") {
               if (i > nf) { if (a[1] ~ /^com2sec/) { print; next } ; nf = i }
               a[i] = rep; out = a[1]
               for (j = 2; j <= nf; j++) out = out " " a[j]
               print lead out; ch++; next
           }
           print }
         END { printf "%d", ch + 0 > "/dev/stderr"; exit(ch ? 0 : 1) }' "$1"
}

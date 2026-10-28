# U-59 (상) 안전한 SNMP 버전 사용 — 조치
# 가이드 조치 방법: SNMP v1/v2 대신 v3 사용. 자동화 범위: v3 계정을 대신 만들어주는 것은
# 비밀번호를 임의로 정해야 해 위험하므로, v1/v2 community 설정을 비활성화(주석 처리)한다.
# check(U-59)와 같이 IPv6 지시어(com2sec6/rocommunity6/rwcommunity6)와 includeFile/includeDir 로 불러온
# 파일까지 대상으로 한다(F-R8 - 예전에는 주 파일만 고쳐 include 파일의 설정이 남아 재검증 실패→원복됐다).
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
    pat='^[[:space:]]*(com2sec6?|rocommunity6?|rwcommunity6?)[[:space:]]'
    done_list=""
    # here-doc 반복문은 현재 셸에서 돈다 - fix_backup 실패 시 중단이 전달된다(| while 금지)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -qE "$pat" "$f" 2>/dev/null || continue
        fix_backup "$f"
        n=$(grep -cE "$pat" "$f")
        if ! sed -E 's/^([[:space:]]*)(com2sec6?|rocommunity6?|rwcommunity6?)([[:space:]])/\1#\2\3/' "$f" > "$f.kisa_tmp" \
            || ! fix_write_back "$f.kisa_tmp" "$f"; then
            rm -f "$f.kisa_tmp"
            FIX_STATUS="ERROR"; FIX_DETAIL="$f 수정 실패"; FIX_EVIDENCE=""
            return
        fi
        done_list="$done_list $f(${n}줄)"
    done <<EOF
$files
EOF
    if [ -z "$done_list" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="v1/v2 community 설정이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="SNMP v1/v2(com2sec/rocommunity/rwcommunity, IPv6 포함) 설정을 주석 처리함:$done_list (v3 전환 필요) — snmpd 재시작 후 적용"
    # community 원문은 남기지 않는다(파일·줄 수만)
    FIX_EVIDENCE="$done_list"
}

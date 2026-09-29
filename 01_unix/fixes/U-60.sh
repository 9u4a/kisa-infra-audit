# U-60 (중) SNMP Community String 복잡성 설정 — 조치
# 자동화 범위: 기본값(public/private) 또는 길이/복잡도 미달 Community String 을 임의 생성한
# 강력한 문자열로 교체한다(영문 대소문자+숫자 16자, /dev/urandom 기반).
run_fix() {
    conf=""
    for f in /etc/snmp/snmpd.conf /etc/net-snmp/snmp/snmpd.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="SNMP 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi

    strings=$(grep -E '^[[:space:]]*(com2sec|rocommunity|rwcommunity)[[:space:]]' "$conf" 2>/dev/null | \
        awk '{ if ($1=="com2sec") print $4; else print $2 }')
    if [ -z "$strings" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="v1/v2 Community String 설정이 없어 조치 불필요(v3 인증정보는 자동 조치 대상 아님)"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$conf"
    applied=""
    for s in $strings; do
        len=${#s}
        has_alpha=0; has_digit=0; has_special=0
        case "$s" in *[A-Za-z]*) has_alpha=1 ;; esac
        case "$s" in *[0-9]*) has_digit=1 ;; esac
        case "$s" in *[!A-Za-z0-9]*) has_special=1 ;; esac
        weak=1
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$len" -ge 10 ]; then weak=0; fi
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$has_special" -eq 1 ] && [ "$len" -ge 8 ]; then weak=0; fi
        [ "$weak" -eq 0 ] && continue
        newstr=$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 16)
        [ -z "$newstr" ] && newstr="Snmp$(date +%s)Str"
        sed -i "s/\b$(printf '%s' "$s" | sed 's/[.[\*^$/]/\\&/g')\b/${newstr}/g" "$conf"
        applied="$applied ${s}->****(신규 16자 문자열)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="모든 Community String 이 이미 복잡도 기준을 충족함"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"
        FIX_DETAIL="기준 미달 Community String 을 새로 생성한 강력한 문자열로 교체함:$applied (snmpd 재시작 및 모니터링 시스템 측 문자열 갱신 필요)"
        FIX_EVIDENCE="$applied"
    fi
}

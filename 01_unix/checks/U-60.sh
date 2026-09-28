# U-60 (중) SNMP Community String 복잡성 설정
# 판단 기준(가이드 원문): 양호 = "public"/"private" 가 아니고, 영문+숫자 10자리 이상 또는
#                        영문+숫자+특수문자 8자리 이상 (v3 인증 비밀번호가 복잡도 만족 시도 양호)
#                        취약 = 기본값 사용 또는 길이/복잡도 미달
# 자동화 범위: net-snmp(snmpd.conf) 의 v1/v2 community string. v3 전용이면 MANUAL(비밀번호 확인 불가).
# SNMP 미사용 시 GOOD.

run_check() {
    conf=""
    for f in /etc/snmp/snmpd.conf /etc/net-snmp/snmp/snmpd.conf; do
        [ -f "$f" ] && conf="$f"
    done

    if [ -z "$conf" ]; then
        if command -v snmpd >/dev/null 2>&1; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="snmpd 는 설치되어 있으나 설정 파일 위치를 찾지 못함"
        else
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="SNMP 서비스가 설치되어 있지 않음"
        fi
        CHECK_EVIDENCE=""
        return
    fi

    strings=$(grep -E '^[[:space:]]*(com2sec|rocommunity|rwcommunity)[[:space:]]' "$conf" 2>/dev/null | \
        awk '{ if ($1=="com2sec") print $4; else print $2 }')

    if [ -z "$strings" ]; then
        if grep -qE '^[[:space:]]*createUser' "$conf" 2>/dev/null; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="SNMP v3(createUser)만 사용 중 — 인증 비밀번호 복잡도는 설정 파일에서 확인할 수 없어 수동 확인 필요"
        else
            CHECK_STATUS="NA"
            CHECK_DETAIL="Community String 설정을 찾지 못함"
        fi
        CHECK_EVIDENCE="$conf"
        return
    fi

    weak=""
    for s in $strings; do
        case "$s" in
            public|private) weak="$weak $s(기본값)" ;;
        esac
        len=${#s}
        has_alpha=0; has_digit=0; has_special=0
        case "$s" in *[A-Za-z]*) has_alpha=1 ;; esac
        case "$s" in *[0-9]*) has_digit=1 ;; esac
        case "$s" in *[!A-Za-z0-9]*) has_special=1 ;; esac
        ok=0
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$len" -ge 10 ]; then ok=1; fi
        if [ "$has_alpha" -eq 1 ] && [ "$has_digit" -eq 1 ] && [ "$has_special" -eq 1 ] && [ "$len" -ge 8 ]; then ok=1; fi
        [ "$ok" -eq 0 ] && weak="$weak ${s}(길이/복잡도 미달)"
    done

    CHECK_EVIDENCE="$conf
검사한 Community String 개수: $(printf '%s\n' "$strings" | grep -c .)"

    if [ -z "$weak" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="모든 Community String 이 기본값이 아니며 길이/복잡도 기준을 충족함"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="기준 미달 Community String 이 존재함:$weak"
    fi
}

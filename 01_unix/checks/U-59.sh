# U-59 (상) 안전한 SNMP 버전 사용
# 판단 기준(가이드 원문): 양호 = SNMP v3 이상 사용 / 취약 = v2 이하 사용
# 자동화 범위: net-snmp(snmpd.conf) 기준. SNMP 미사용 시 GOOD.

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

    # 진단 검수 U-R15: includeFile/includeDir 로 불러오는 파일과 IPv6 지시어(com2sec6/rocommunity6/rwcommunity6)까지 본다.
    all_lines=$(snmpd_conf_lines "$conf")
    unread=$(printf '%s\n' "$all_lines" | awk -F'\t' '$1 == "!unread" { printf "%s ", $2 }')
    all_lines=$(printf '%s\n' "$all_lines" | grep -v '^!unread')
    v3_users=$(printf '%s\n' "$all_lines" | grep -E '^[[:space:]]*createUser')
    v12_lines=$(printf '%s\n' "$all_lines" | grep -E '^[[:space:]]*(com2sec6?|rocommunity6?|rwcommunity6?)[[:space:]]')

    CHECK_EVIDENCE="$conf
v3 createUser 라인 수: $(printf '%s\n' "$v3_users" | grep -c .)
v1/v2 community 라인 수: $(printf '%s\n' "$v12_lines" | grep -c .)"

    if [ -n "$v12_lines" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="SNMP v1/v2(com2sec/rocommunity/rwcommunity) 설정이 존재함"
    elif [ -n "$unread" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="include 된 SNMP 설정 파일을 읽지 못해 확인하지 못함: $unread"
    elif [ -n "$v3_users" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="SNMP v3(createUser) 설정만 존재함"
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="$conf 에서 SNMP 버전 관련 설정을 찾지 못함"
    fi
}

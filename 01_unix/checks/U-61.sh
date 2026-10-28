# U-61 (상) SNMP Access Control 설정
# 판단 기준(가이드 원문): 양호 = SNMP 접근 제어(허용 네트워크 등)가 설정된 경우 / 취약 = 미설정
# 자동화 범위: net-snmp(snmpd.conf) com2sec/rocommunity/rwcommunity 의 소스 제한 인자 확인.
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

    # 진단 검수 U-R15: includeFile/includeDir 로 불러오는 파일과 IPv6 지시어(com2sec6/rocommunity6/rwcommunity6)까지 본다.
    all_lines=$(snmpd_conf_lines "$conf")
    unread=$(printf '%s\n' "$all_lines" | awk -F'\t' '$1 == "!unread" { printf "%s ", $2 }')
    all_lines=$(printf '%s\n' "$all_lines" | grep -v '^!unread')
    lines=$(printf '%s\n' "$all_lines" | grep -E '^[[:space:]]*(com2sec6?|rocommunity6?|rwcommunity6?)[[:space:]]')

    if [ -z "$lines" ]; then
        if [ -n "$unread" ]; then
            CHECK_STATUS="ERROR"
            CHECK_DETAIL="include 된 SNMP 설정 파일을 읽지 못해 확인하지 못함: $unread"
        elif printf '%s\n' "$all_lines" | grep -qE '^[[:space:]]*createUser'; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="SNMP v3 사용 중 — net-snmp 는 v3 에서도 별도 접근제어(view/context) 설정이 가능하므로 수동 확인 필요"
        else
            CHECK_STATUS="NA"
            CHECK_DETAIL="Community String 설정을 찾지 못함"
        fi
        CHECK_EVIDENCE="$conf"
        return
    fi

    unrestricted=""
    old_ifs=$IFS; IFS='
'
    for line in $lines; do
        IFS=$old_ifs
        set -f   # community 에 '*' 등이 있어도 파일명으로 펼치지 않는다
        # shellcheck disable=SC2086
        set -- $line
        set +f
        # com2sec <secname> <source> <community> / rocommunity|rwcommunity <community> [<source>]
        # 두 문법 모두 소스 제한 인자가 3번째 필드에 위치함 (rocommunity 는 생략 가능 = 전체 허용)
        # ${3:-}: 소스를 생략한 "rocommunity <값>" 줄에서 set -u 로 진단 전체가 죽었다(진단 실행 검수로 발견)
        source_field=${3:-}
        case "$source_field" in
            default|0.0.0.0/0|::/0|""|any) unrestricted="$unrestricted
$line" ;;
        esac
        IFS='
'
    done
    IFS=$old_ifs

    # community 문자열은 비밀번호에 준하므로 증적/판정 문구에 원문을 남기지 않는다.
    CHECK_EVIDENCE="$conf
$(printf '%s\n' "$lines" | _u61_mask)"

    if [ -z "$unrestricted" ] && [ -n "$unread" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="include 된 SNMP 설정 파일을 읽지 못해 일부 접근 제어 설정을 확인하지 못함: $unread"
    elif [ -z "$unrestricted" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="SNMP 접근이 특정 네트워크로 제한되어 있음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="SNMP 접근 제어(허용 네트워크) 없이 전체 허용된 설정이 존재함:$(printf '%s\n' "$unrestricted" | _u61_mask)"
    fi
}

# com2sec <secname> <source> <community> / rocommunity|rwcommunity <community> [<source>]
_u61_mask() {
    awk '{ i = ($1 ~ /^com2sec6?$/) ? 4 : 2
           if (i <= NF) { s = $i; $i = (length(s) <= 4) ? "***(" length(s) "자)" : substr(s, 1, 2) "***(" length(s) "자)" }
           print }'
}

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

    lines=$(grep -E '^[[:space:]]*(com2sec|rocommunity|rwcommunity)[[:space:]]' "$conf" 2>/dev/null)

    if [ -z "$lines" ]; then
        if grep -qE '^[[:space:]]*createUser' "$conf" 2>/dev/null; then
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
        set -- $line
        # com2sec <secname> <source> <community> / rocommunity|rwcommunity <community> [<source>]
        # 두 문법 모두 소스 제한 인자가 3번째 필드에 위치함 (rocommunity 는 생략 가능 = 전체 허용)
        source_field=$3
        case "$source_field" in
            default|0.0.0.0/0|""|any) unrestricted="$unrestricted
$line" ;;
        esac
        IFS='
'
    done
    IFS=$old_ifs

    CHECK_EVIDENCE="$conf
$lines"

    if [ -z "$unrestricted" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="SNMP 접근이 특정 네트워크로 제한되어 있음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="SNMP 접근 제어(허용 네트워크) 없이 전체 허용된 설정이 존재함:$unrestricted"
    fi
}

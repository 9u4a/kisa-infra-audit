# U-50 (상) DNS ZoneTransfer 설정
# 판단 기준(가이드 원문): 양호 = Zone Transfer 를 허가된 사용자에게만 허용 / 취약 = 전체 허용
# 자동화 범위: BIND(named.conf/named.conf.options) allow-transfer 설정. DNS 미사용 시 GOOD.

run_check() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf.options /etc/bind/named.conf; do
        [ -f "$f" ] && conf="$f"
    done

    if [ -z "$conf" ]; then
        if command -v named >/dev/null 2>&1; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="named 는 설치되어 있으나 설정 파일 위치를 찾지 못함"
        else
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="DNS 서비스(BIND/named)가 설치되어 있지 않음"
        fi
        CHECK_EVIDENCE=""
        return
    fi

    line=$(grep -iE 'allow-transfer' "$conf" 2>/dev/null | head -n1)
    CHECK_EVIDENCE="$conf: ${line:-allow-transfer 미설정}"

    if [ -z "$line" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-transfer 설정이 없어 기본적으로 모든 사용자에게 Zone Transfer 가 허용됨"
    elif printf '%s' "$line" | grep -qiE 'any[[:space:]]*;'; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-transfer 가 any(전체 허용)로 설정되어 있음"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-transfer 가 특정 대상으로 제한되어 있음"
    fi
}

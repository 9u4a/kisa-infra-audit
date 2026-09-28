# U-51 (중) DNS 서비스의 취약한 동적 업데이트 설정 금지
# 판단 기준(가이드 원문): 양호 = 동적 업데이트 비활성화 또는 활성화 시 접근통제 적용
#                        취약 = 활성화되어 있고 접근통제 없음
# 자동화 범위: BIND allow-update 설정. DNS 미사용 시 GOOD.

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

    line=$(grep -iE 'allow-update' "$conf" 2>/dev/null | head -n1)
    CHECK_EVIDENCE="$conf: ${line:-allow-update 미설정(기본값 none)}"

    if [ -z "$line" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-update 설정이 없어 동적 업데이트가 기본적으로 비활성화됨"
    elif printf '%s' "$line" | grep -qiE 'none[[:space:]]*;'; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-update 가 none 으로 설정되어 동적 업데이트가 비활성화됨"
    elif printf '%s' "$line" | grep -qiE 'any[[:space:]]*;'; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-update 가 any(전체 허용)로 설정되어 있음"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-update 가 특정 대상으로 제한되어 있음"
    fi
}

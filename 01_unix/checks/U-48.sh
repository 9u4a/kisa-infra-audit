# U-48 (중) expn, vrfy 명령어 제한
# 판단 기준(가이드 원문): 양호 = noexpn/novrfy(또는 동등 설정) 적용, 또는 메일 서비스 미사용
#                        취약 = 미적용
# 자동화 범위: Sendmail(PrivacyOptions), Postfix(disable_vrfy_command).

run_check() {
    checked=0
    violations=""; unverified=""
    evidence=""

    if [ -f /etc/mail/sendmail.cf ]; then
        checked=1
        line=$(grep -iE '^O[[:space:]]*PrivacyOptions' /etc/mail/sendmail.cf 2>/dev/null | tail -n1)
        evidence="$evidence
sendmail.cf PrivacyOptions: ${line:-미설정}"
        ok=0
        printf '%s' "$line" | grep -qi 'goaway' && ok=1
        printf '%s' "$line" | grep -qi 'novrfy' && printf '%s' "$line" | grep -qi 'noexpn' && ok=1
        [ "$ok" -eq 1 ] || violations="$violations sendmail(noexpn/novrfy/goaway 없음)"
    fi

    if command -v postconf >/dev/null 2>&1; then
        checked=1
        # postconf 가 실패하면(시간 초과·설정 오류) 값이 비어 "미설정 = 취약"으로 보이므로 따로 기록한다
        if vrfy=$(run_to 15 postconf -h disable_vrfy_command 2>/dev/null); then
            evidence="$evidence
postfix disable_vrfy_command: ${vrfy:-미설정(기본값 no)}"
            [ "$vrfy" = "yes" ] || violations="$violations postfix(disable_vrfy_command=yes 아님)"
        else
            unverified="postfix(postconf 조회 실패 - 확인 못 함)"
        fi
    fi

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="메일 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ] && [ -n "$unverified" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="설정을 조회하지 못해 확인하지 못함: $unverified"
        CHECK_EVIDENCE="$evidence"
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="expn/vrfy 명령어 제한이 설정되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="expn/vrfy 명령어 제한이 설정되어 있지 않음:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

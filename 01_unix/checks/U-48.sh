# U-48 (중) expn, vrfy 명령어 제한
# 판단 기준(가이드 원문): 양호 = noexpn/novrfy(또는 동등 설정) 적용, 또는 메일 서비스 미사용
#                        취약 = 미적용
# 자동화 범위: Sendmail(PrivacyOptions), Postfix(disable_vrfy_command).

run_check() {
    checked=0
    violations=""
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
        vrfy=$(postconf -h disable_vrfy_command 2>/dev/null)
        evidence="$evidence
postfix disable_vrfy_command: ${vrfy:-미설정(기본값 no)}"
        [ "$vrfy" = "yes" ] || violations="$violations postfix(disable_vrfy_command=yes 아님)"
    fi

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="메일 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
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

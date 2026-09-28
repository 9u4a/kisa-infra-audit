# U-47 (상) 스팸 메일 릴레이 제한
# 판단 기준(가이드 원문): 양호 = 릴레이 제한 설정됨(또는 메일 서비스 미사용) / 취약 = 미설정
# 자동화 범위: Postfix(smtpd_relay_restrictions/smtpd_recipient_restrictions 에
#             reject_unauth_destination 포함 여부), Sendmail(promiscuous_relay 미사용 여부).

run_check() {
    checked=0
    violations=""
    evidence=""

    if command -v postconf >/dev/null 2>&1; then
        checked=1
        relay=$(postconf -h smtpd_relay_restrictions 2>/dev/null)
        recipient=$(postconf -h smtpd_recipient_restrictions 2>/dev/null)
        evidence="$evidence
postfix smtpd_relay_restrictions: ${relay:-미설정}
postfix smtpd_recipient_restrictions: ${recipient:-미설정}"
        if ! printf '%s %s' "$relay" "$recipient" | grep -q 'reject_unauth_destination'; then
            violations="$violations postfix(reject_unauth_destination 없음)"
        fi
    fi

    if [ -f /etc/mail/sendmail.mc ] || [ -f /etc/mail/sendmail.cf ]; then
        checked=1
        promiscuous=$(grep -il 'promiscuous_relay' /etc/mail/sendmail.mc /etc/mail/sendmail.cf 2>/dev/null | grep -v '^#')
        access_file="/etc/mail/access"
        access_exists=0
        [ -f "$access_file" ] && access_exists=1
        evidence="$evidence
sendmail promiscuous_relay 검색 결과: ${promiscuous:-없음}
$access_file 존재 여부: $access_exists"
        if [ -n "$promiscuous" ]; then
            violations="$violations sendmail(promiscuous_relay 설정됨)"
        fi
    fi

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="메일 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="스팸 메일 릴레이 제한이 설정되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="스팸 메일 릴레이 제한이 설정되어 있지 않음:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

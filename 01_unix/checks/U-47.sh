# U-47 (상) 스팸 메일 릴레이 제한
# 판단 기준(가이드 원문): 양호 = 릴레이 제한 설정됨(또는 메일 서비스 미사용) / 취약 = 미설정
# 자동화 범위: Postfix(smtpd_relay_restrictions/smtpd_recipient_restrictions 에
#             reject_unauth_destination 포함 여부), Sendmail(promiscuous_relay 미사용 여부).

run_check() {
    checked=0
    violations=""; unverified=""
    evidence=""

    if command -v postconf >/dev/null 2>&1; then
        checked=1
        # postconf 가 실패하면(시간 초과·설정 오류) 값이 비어 "미설정 = 취약"으로 보이므로 따로 기록한다
        pc_fail=""
        relay=$(run_to 15 postconf -h smtpd_relay_restrictions 2>/dev/null) || pc_fail=1
        recipient=$(run_to 15 postconf -h smtpd_recipient_restrictions 2>/dev/null) || pc_fail=1
        evidence="$evidence
postfix smtpd_relay_restrictions: ${relay:-미설정}
postfix smtpd_recipient_restrictions: ${recipient:-미설정}"
        # 진단 검수 U-R17: Postfix 2.10+ 기본값 smtpd_relay_restrictions 는 "permit_mynetworks, permit_sasl_authenticated,
        # defer_unauth_destination" 이라 미설정이어도 릴레이가 제한된다(postconf -h 는 기본값 포함 실효값을 출력) -
        # 예전에는 reject_unauth_destination 만 인정해 기본 설치가 거짓 VULN 이었다.
        if [ -n "$pc_fail" ]; then
            unverified="postfix(postconf 조회 실패 - 확인 못 함)"
        elif ! printf '%s %s' "$relay" "$recipient" | grep -qE '(reject|defer)_unauth_destination'; then
            violations="$violations postfix(reject/defer_unauth_destination 없음)"
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
    elif [ -z "$violations" ] && [ -n "$unverified" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="설정을 조회하지 못해 확인하지 못함: $unverified"
        CHECK_EVIDENCE="$evidence"
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

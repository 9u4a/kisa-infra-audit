# U-46 (상) 일반 사용자의 메일 서비스 실행 방지
# 판단 기준(가이드 원문): 양호 = 일반 사용자의 메일 서비스 q옵션(큐 조작) 실행 방지 설정됨
#                        취약 = 설정되어 있지 않음
# 자동화 범위: Sendmail(PrivacyOptions restrictqrun), Postfix(postsuper), Exim(exiqgrep).
# 메일 서비스 미사용 시 GOOD.

run_check() {
    checked=0
    violations=""
    evidence=""

    if [ -f /etc/mail/sendmail.cf ]; then
        checked=1
        line=$(grep -iE '^O[[:space:]]*PrivacyOptions' /etc/mail/sendmail.cf 2>/dev/null | tail -n1)
        evidence="$evidence
sendmail.cf PrivacyOptions: ${line:-미설정}"
        printf '%s' "$line" | grep -qi 'restrictqrun' || violations="$violations sendmail(restrictqrun 없음)"
    fi

    if [ -x /usr/sbin/postsuper ]; then
        checked=1
        perm=$(stat -c '%a' /usr/sbin/postsuper 2>/dev/null)
        evidence="$evidence
/usr/sbin/postsuper 권한: $perm"
        find /usr/sbin/postsuper -perm -0001 2>/dev/null | grep -q . && violations="$violations postfix(postsuper 일반사용자 실행권한)"
    fi

    if [ -x /usr/sbin/exiqgrep ]; then
        checked=1
        perm=$(stat -c '%a' /usr/sbin/exiqgrep 2>/dev/null)
        evidence="$evidence
/usr/sbin/exiqgrep 권한: $perm"
        find /usr/sbin/exiqgrep -perm -0001 2>/dev/null | grep -q . && violations="$violations exim(exiqgrep 일반사용자 실행권한)"
    fi

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="메일 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="일반 사용자의 메일 큐 조작(q옵션)이 제한되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="일반 사용자의 메일 큐 조작이 제한되어 있지 않음:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

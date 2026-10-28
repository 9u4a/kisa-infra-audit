# U-45 (상) 메일 서비스 버전 점검
# 판단 기준(가이드 원문): 양호 = 메일 서비스 버전이 최신인 경우 / 취약 = 최신이 아닌 경우
# "최신 버전"은 오프라인에서 CVE/배포 최신본과 비교할 수 없으므로, 설치된 메일 서비스와
# 버전을 확인해 관리자가 최신 여부를 판단하도록 MANUAL 로 제공한다. 미설치 시 GOOD.

run_check() {
    evidence=""

    if command -v postconf >/dev/null 2>&1; then
        v=$(run_to 10 postconf mail_version 2>/dev/null)
        evidence="$evidence
Postfix: $v"
    fi
    # Postfix 가 있으면 sendmail 은 Postfix 호환 래퍼라 -bt 를 지원하지 않고 maillog 에 오류를 남길 수
    # 있어 실행하지 않는다. 실제 Sendmail 은 시작 시 FQDN 조회로 DNS 장애 때 멈출 수 있어 시간 제한을 둔다.
    if command -v sendmail >/dev/null 2>&1 && ! command -v postconf >/dev/null 2>&1; then
        v=$(run_to 10 sendmail -d0.1 -bt </dev/null 2>/dev/null | grep -i version)
        evidence="$evidence
Sendmail: ${v:-버전 확인 실패}"
    fi
    if command -v exim >/dev/null 2>&1 || command -v exim4 >/dev/null 2>&1; then
        v=$( (run_to 10 exim -bV 2>/dev/null || run_to 10 exim4 -bV 2>/dev/null) | head -n1)
        evidence="$evidence
Exim: $v"
    fi

    if [ -z "$evidence" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="Sendmail/Postfix/Exim 메일 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="설치된 메일 서비스 버전이 최신인지 벤더 홈페이지/CVE 목록과 비교하는 수동 확인이 필요함"
        CHECK_EVIDENCE="$evidence"
    fi
}

# U-66 (중) 정책에 따른 시스템 로깅 설정
# 판단 기준(가이드 원문): 양호 = 로그 기록 정책이 수립되어 있고 정책에 따라 로그를 남기는 경우
#                        취약 = 정책 미수립 또는 로그를 남기지 않는 경우
# "정책 부합 여부"는 조직 정책 문서와 대조해야 하므로 완전 자동 판정은 불가능하다.
# 자동화 범위: rsyslog/syslog 서비스 가동 여부 + 최소 로깅 규칙(auth 등) 존재 여부까지는 자동 판정,
#             정책 문서와의 일치 여부는 MANUAL 로 보완 안내.

run_check() {
    conf=""
    for f in /etc/rsyslog.conf /etc/syslog.conf; do
        [ -f "$f" ] && conf="$f"
    done

    service_active=0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet rsyslog 2>/dev/null && service_active=1
        systemctl is-active --quiet syslog 2>/dev/null && service_active=1
        systemctl is-active --quiet syslog-ng 2>/dev/null && service_active=1
    fi
    pgrep -f 'rsyslogd|syslogd|syslog-ng' >/dev/null 2>&1 && service_active=1

    if [ "$service_active" -eq 0 ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="시스템 로깅 서비스(rsyslog/syslog)가 실행 중이지 않음"
        CHECK_EVIDENCE="conf=${conf:-없음}"
        return
    fi

    rules=""
    [ -n "$conf" ] && rules=$(grep -vE '^[[:space:]]*(#|$)' "$conf" 2>/dev/null)
    auth_logged=$(printf '%s' "$rules" | grep -icE 'auth')

    if [ -z "$rules" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="로깅 서비스는 실행 중이나 $conf 에 유효한 로깅 규칙이 없음"
    elif [ "$auth_logged" -eq 0 ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="로깅 서비스는 실행 중이나 인증(auth) 관련 로깅 규칙을 찾지 못함 — 조직 로깅 정책과 대조해 수동 확인 필요"
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="로깅 서비스가 실행 중이고 기본 규칙이 존재함 — 조직의 로깅 정책 문서와 일치하는지는 수동 확인 필요"
    fi
    CHECK_EVIDENCE="$conf:
$rules"
}

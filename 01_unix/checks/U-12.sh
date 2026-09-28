# U-12 (하) 세션 종료 시간 설정
# 판단 기준(가이드 원문): 양호 = Session Timeout 이 600초(10분) 이하로 설정된 경우
#                        취약 = 그렇지 않은 경우
# 자동화 범위: sh/ksh/bash 계열의 TMOUT (/etc/profile, /etc/profile.d/*.sh) 만 판정.
# csh/tcsh(autologout)는 최근 배포판 기본 쉘이 아니므로 0.1.0 범위에서는 MANUAL 로 안내.

run_check() {
    files="/etc/profile"
    for f in /etc/profile.d/*.sh; do
        [ -f "$f" ] && files="$files $f"
    done

    tmout=""
    exported=0
    evidence=""
    for f in $files; do
        [ -f "$f" ] || continue
        line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?TMOUT=[0-9]+' "$f" 2>/dev/null | tail -n1)
        if [ -n "$line" ]; then
            evidence="$evidence
$f: $line"
            v=$(printf '%s' "$line" | sed -nE 's/.*TMOUT=([0-9]+).*/\1/p')
            [ -n "$v" ] && tmout="$v"
        fi
        grep -qE '^[[:space:]]*export[[:space:]]+TMOUT([[:space:]]|$)' "$f" 2>/dev/null && exported=1
    done

    if [ -z "$tmout" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="TMOUT 설정을 찾을 수 없음 (Session Timeout 미설정)"
        CHECK_EVIDENCE="확인 대상: $files"
    elif [ "$tmout" -le 600 ] 2>/dev/null && [ "$exported" -eq 1 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="TMOUT=${tmout}초로 설정되어 600초 이하 기준을 충족함"
        CHECK_EVIDENCE="$evidence"
    elif [ "$tmout" -le 600 ] 2>/dev/null; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="TMOUT=${tmout}초는 기준을 충족하나 export 여부를 확인하지 못함 (하위 쉘에 전파되지 않을 수 있음)"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="TMOUT=${tmout}초로 600초를 초과하여 설정됨"
        CHECK_EVIDENCE="$evidence"
    fi
}

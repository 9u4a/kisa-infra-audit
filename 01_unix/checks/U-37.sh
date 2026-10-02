# U-37 (상) crontab 설정파일 권한 설정 미흡
# 판단 기준(가이드 원문): 양호 = crontab/at 명령어 실행 권한 제한(750 이하) 및 관련 파일 권한 640 이하
#                        취약 = 그 외
# 자동화 범위: LINUX(rhel/debian) 기준 대표 경로만 판정.

run_check() {
    evidence=""
    violations=""
    checked=0

    for bin in /usr/bin/crontab /usr/bin/at; do
        [ -e "$bin" ] || continue
        checked=1
        perm=$(stat -L -c '%a' "$bin" 2>/dev/null)
        evidence="$evidence
$(ls -l "$bin" 2>/dev/null)"
        if [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null; then
            violations="$violations $bin(perm=$perm)"
        fi
        suid=$(find "$bin" -perm -4000 2>/dev/null)
        [ -n "$suid" ] && violations="$violations $bin(SUID 설정됨)"
    done

    for d in /var/spool/cron /var/spool/cron/crontabs /var/spool/at /var/spool/cron/atjobs; do
        [ -d "$d" ] || continue
        checked=1
        bad=$(find "$d" -maxdepth 1 -type f -perm -0007 2>/dev/null)
        evidence="$evidence
$d: $(ls -l "$d" 2>/dev/null | tr '\n' ' ')"
        [ -n "$bad" ] && violations="$violations $d(other-perm 파일 존재)"
    done

    if [ -f /etc/cron.allow ] || [ -f /etc/cron.deny ]; then
        checked=1
        for f in /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
            [ -f "$f" ] || continue
            perm=$(stat -L -c '%a' "$f" 2>/dev/null)
            evidence="$evidence
$(ls -l "$f" 2>/dev/null)"
            [ -n "$perm" ] && [ "$perm" -gt 640 ] 2>/dev/null && violations="$violations $f(perm=$perm)"
        done
    fi

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="cron/at 관련 파일 위치를 확인하지 못함 (배포판별 경로 상이) — 수동 확인 필요"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="crontab/at 명령어 및 cron/at 관련 파일 권한이 기준을 충족함"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="기준을 초과하는 권한이 설정된 cron/at 관련 파일이 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

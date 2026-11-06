# U-37 (상) crontab 설정파일 권한 설정 미흡
# 판단 기준(가이드 원문): 양호 = crontab/at 명령어 실행 권한 제한(750 이하) 및 관련 파일 권한 640 이하
#                        취약 = 그 외
# 자동화 범위: LINUX(rhel/debian) 기준 대표 경로만 판정.
# 1.5.0 A1: 예전에는 스풀 파일을 -perm -0007(기타 rwx 가 "모두" 있을 때만)로 봐서 0644·0666 작업 목록을 놓쳤고,
# /etc/crontab·/etc/cron.d 는 보지 않았다. 이제 관련 파일마다 perm_exceeds 로 기준(640)과 비트 단위 비교한다.
# 기준에서 벗어나는 부분(guide.json deviation):
#   - at 작업 목록 파일은 소유자 실행 비트(atd 가 "실행 대기" 표시로 쓴다)를 허용해 740 기준으로 본다.
#   - /etc/cron.{hourly,daily,weekly,monthly} 안의 파일은 run-parts 가 실행하는 스크립트라 640 을 적용하면 실행이
#     멈춘다 - 판정에서 빼고 증적에만 남긴다.

# u37_files <디렉터리> -- 바로 아래 일반 파일(숨김 포함)
u37_files() { find "$1" -maxdepth 1 -type f 2>/dev/null; }

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
        if [ -z "$perm" ]; then
            violations="$violations $bin(권한 확인 불가)"
        elif perm_exceeds "$perm" 750; then
            violations="$violations $bin(perm=$perm)"
        fi
    done

    # <경로> <기준> -- 관련 파일 한 개 판정
    u37_file() {
        _p=$(stat -L -c '%a' "$1" 2>/dev/null)
        evidence="$evidence
$(ls -l "$1" 2>/dev/null)"
        if [ -z "$_p" ]; then
            violations="$violations $1(권한 확인 불가)"
        elif perm_exceeds "$_p" "$2"; then
            violations="$violations $1(perm=$_p)"
        fi
    }

    # 작업 목록(스풀). 스풀 디렉터리는 보통 root 만 읽을 수 있다 - 못 읽으면 위반 파일이 안 보여 거짓 GOOD 이 된다
    for d in /var/spool/cron /var/spool/cron/crontabs /var/spool/at /var/spool/cron/atjobs; do
        [ -d "$d" ] || continue
        checked=1
        if [ ! -r "$d" ] || [ ! -x "$d" ]; then
            CHECK_STATUS="ERROR"; CHECK_DETAIL="$d 를 읽을 수 없음(권한 부족) - root 로 실행 필요"; CHECK_EVIDENCE=""
            return
        fi
        lim=640
        case "$d" in /var/spool/at|/var/spool/cron/atjobs) lim=740 ;; esac
        evidence="$evidence
[$d]"
        while IFS= read -r f; do
            [ -n "$f" ] && u37_file "$f" "$lim"
        done <<EOF
$(u37_files "$d")
EOF
    done

    # cron 설정 파일(/etc/crontab, /etc/cron.d/*)과 허용·차단 목록
    for f in /etc/crontab /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
        [ -f "$f" ] || continue
        checked=1
        u37_file "$f" 640
    done
    if [ -d /etc/cron.d ]; then
        checked=1
        while IFS= read -r f; do
            [ -n "$f" ] && u37_file "$f" 640
        done <<EOF
$(u37_files /etc/cron.d)
EOF
    fi
    for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        [ -d "$d" ] || continue
        evidence="$evidence
[$d - 실행 스크립트 폴더, 640 판정 제외] $(ls -l "$d" 2>/dev/null | sed 1d | awk '{ print $1, $NF }' | tr '\n' ' ')"
    done

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="cron/at 관련 파일 위치를 확인하지 못함 (배포판별 경로 상이) — 수동 확인 필요"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="crontab/at 명령어(750 이하) 및 cron/at 관련 파일(640 이하) 권한이 기준을 충족함"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="기준을 초과하는 권한이 설정된 cron/at 관련 파일이 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

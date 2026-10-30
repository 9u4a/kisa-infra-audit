#!/bin/sh
# 03_web/tests/fixtures/cases/run_case.sh <engine> <코드> <케이스 이름> <기대 상태>
#   engine: apache | apache-debian | nginx | tomcat (컨테이너 안, 저장소 루트(/infra)에서 실행)
# 항목별 케이스(cases.json 의 한 줄)를 깨끗한 이미지에서 실행하고 결과를 KEY=VALUE 줄로 출력한다(판정은 run_tests.sh).
#   1) cases/<engine>/<코드>_<이름>.sh 를 set -e 서브셸에서 실행(설정 변경·프로세스 기동) → SETUP_RC
#      전후 상태(설정·웹 경로·로그 폴더의 경로/권한/소유자/내용, 웹 엔진 프로세스 comm/uid)가 달라졌는지 → CHANGED
#      (케이스가 아무것도 바꾸지 못했는데 기본값이 우연히 기대값과 같아 통과하는 것을 막는다)
#   2) run.sh -e <엔진> -i <코드> → STATUS
#   3) 기대 상태가 VULN 이고 fixes/<코드>.sh 가 있으면(auto/confirm) 조치 검증. 케이스 파일 머리의
#        # FIX: GOOD | MANUAL          조치 적용(APPLIED) → 재진단 그 상태, 문법 검사 통과, --rollback 후 케이스 직후 상태와 동일
#        # FIX: NONE <사유>             조치가 적용되지 않아야 함(수동 조치 안내·ERROR) → 상태 무변경, 재진단 VULN 유지
#        # FIX: SKIP <사유>             조치 검증 생략(사유 필수 - 예: 가짜 프로세스로만 재현한 상태)
#        # FIX_INPUT: a|b|c             가상 터미널에 먼저 넣을 입력(그 뒤로는 y 를 계속 넣음 - confirm 등급 승인)
#      지시가 없으면 GOOD 을 기대한다. confirm 등급은 fix_safety.sh 와 같이 script 로 만든 가상 터미널로 승인한다.
# 출력: SETUP_RC CHANGED STATUS DETAIL FIX_MODE FIX_WHY FIX_RC FIX_RESULT FIX_RECHECK BASE_SYNTAX_RC FIX_SYNTAX_RC FIX_STATE ROLLBACK
set -u
ENGINE=$1; CODE=$2; NAME=$3; EXPECT=$4
CASE="03_web/tests/fixtures/cases/$ENGINE/${CODE}_$NAME.sh"
OUT=/tmp/kisa_case_fix

case "$ENGINE" in
    apache) RUN_E=apache; TEST="httpd -t"
            DIRS="/usr/local/apache2/conf /usr/local/apache2/htdocs /usr/local/apache2/cgi-bin /usr/local/apache2/logs /srv" ;;
    apache-debian) RUN_E=apache; TEST="apache2ctl -t"; DIRS="/etc/apache2 /var/www /var/log/apache2 /srv" ;;
    nginx) RUN_E=nginx; TEST="nginx -t"; DIRS="/etc/nginx /usr/share/nginx /var/log/nginx /srv" ;;
    tomcat) RUN_E=tomcat; TEST=tc_test
            DIRS="/usr/local/tomcat/conf /usr/local/tomcat/webapps /usr/local/tomcat/logs /srv" ;;
    *) echo "usage: run_case.sh <apache|apache-debian|nginx|tomcat> <code> <name> <expect>" >&2; exit 2 ;;
esac

# tc_test -> Tomcat 설정 검사(catalina.sh configtest, 임시 CATALINA_BASE 에 conf 만 링크 - fix_safety.sh 와 같음)
tc_test() {
    mkdir -p /tmp/kisa_cb/logs /tmp/kisa_cb/temp /tmp/kisa_cb/work
    ln -sfn /usr/local/tomcat/conf /tmp/kisa_cb/conf
    CATALINA_BASE=/tmp/kisa_cb /usr/local/tomcat/bin/catalina.sh configtest
}

# snap [conf] -> 상태 목록(conf 를 주면 프로세스 제외). 로그 폴더 안 파일은 내용(실행 중 서버가 계속 씀) 대신 경로·권한·소유자만 본다.
snap() {
    for d in $DIRS; do [ -e "$d" ] && find "$d" -print 2>/dev/null; done | LC_ALL=C sort | while IFS= read -r p; do
        if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
        elif [ -f "$p" ]; then
            case "$p" in
                */logs/*|/var/log/*) printf 'F %s %s\n' "$p" "$(stat -c '%a %u %g' "$p")" ;;
                *) printf 'F %s %s %s\n' "$p" "$(stat -c '%a %u %g' "$p")" "$(cksum < "$p")" ;;
            esac
        else printf 'D %s %s\n' "$p" "$(stat -c '%a %u %g' "$p")"; fi
    done
    [ "${1:-}" = conf ] && return 0   # 조치 검증(원복 동일성)은 설정 트리만 본다 - 조치의 reload 로 바뀐 프로세스는 원복 대상이 아님
    for p in /proc/[0-9]*; do
        c=""; { IFS= read -r c < "$p/comm"; } 2>/dev/null
        case "$c" in httpd|apache2|nginx|java)
            printf 'P %s %s\n' "$c" "$(awk '/^Uid:/ { print $2 }' "$p/status" 2>/dev/null)" ;;
        esac
    done | LC_ALL=C sort
}

# status_of <코드> -> 진단 결과(run.sh -i, 출력 폴더는 매번 새로)
status_of() {
    rm -rf /tmp/kisa_case_run
    sh 03_web/run.sh -e "$RUN_E" -i "$1" -o /tmp/kisa_case_run >/dev/null 2>&1 < /dev/null
    _r=$(ls /tmp/kisa_case_run/*/result.json 2>/dev/null | head -n 1)
    [ -n "$_r" ] || { echo "NO_RESULT"; return; }
    tr -d '\n' < "$_r" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[A-Z]+"' | head -n 1 | sed -E 's/.*"([A-Z]+)"$/\1/'
}

if [ ! -f "$CASE" ]; then
    echo "SETUP_RC=missing"; exit 0
fi
snap > /tmp/case.before
# shellcheck disable=SC1090  # 케이스 파일은 인자로 정해짐
( set -e; . "./$CASE" ) > /tmp/case.setup.log 2>&1
echo "SETUP_RC=$?"
[ -s /tmp/case.setup.log ] && sed 's/^/  SETUPLOG: /' /tmp/case.setup.log | tail -n 5
snap > /tmp/case.after
if cmp -s /tmp/case.before /tmp/case.after; then echo "CHANGED=no"; else echo "CHANGED=yes"; fi

rm -rf /tmp/kisa_case_run
sh 03_web/run.sh -e "$RUN_E" -i "$CODE" -o /tmp/kisa_case_run >/dev/null 2>&1 < /dev/null
R=$(ls /tmp/kisa_case_run/*/result.json 2>/dev/null | head -n 1)
if [ -z "$R" ]; then
    echo "STATUS=NO_RESULT"; exit 0
fi
cp "$R" /tmp/case.result.json
echo "STATUS=$(tr -d '\n' < "$R" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[A-Z]+"' | head -n 1 | sed -E 's/.*"([A-Z]+)"$/\1/')"
echo "DETAIL=$(tr -d '\n' < "$R" | grep -oE '"detail"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -n 1 | cut -c1-240)"

# ---- 조치 검증 ----
# shellcheck disable=SC1091
grade=$(. lib/common.sh >/dev/null 2>&1; guide_field 03_web/guide.json "$CODE" fix)
mode=$(sed -n 's/^# FIX:[[:space:]]*\([A-Z]*\).*/\1/p' "$CASE" | head -n 1)
why=$(sed -n 's/^# FIX:[[:space:]]*[A-Z]*[[:space:]]*//p' "$CASE" | head -n 1)
if [ "$EXPECT" != VULN ] || [ ! -f "03_web/fixes/$CODE.sh" ] || [ "$grade" = manual ] || [ -z "$grade" ]; then
    echo "FIX_MODE=n/a"; exit 0
fi
mode=${mode:-GOOD}
echo "FIX_MODE=$mode"
echo "FIX_WHY=$why"
[ "$mode" = SKIP ] && exit 0
command -v script >/dev/null 2>&1 || { echo "FIX_RC=no_script"; exit 0; }

input=$(sed -n 's/^# FIX_INPUT:[[:space:]]*//p' "$CASE" | head -n 1)
$TEST >/dev/null 2>&1
echo "BASE_SYNTAX_RC=$?"
snap conf > /tmp/case.prefix
# 먼저 FIX_INPUT 을 한 줄씩, 그 뒤로는 y 를 천천히 넣는다(fix_safety.sh 와 같은 방식 - 터미널 에코가 로그를 채우지 않게)
( IFS='|'; for a in $input; do echo "$a"; sleep 0.3; done; while echo y; do sleep 0.3; done ) 2>/dev/null | \
    script -qec "sh 03_web/fix.sh -r /tmp/case.result.json -o '$OUT' -i '$CODE' --apply --yes" /dev/null > /tmp/case.fix.log 2>&1
echo "FIX_RC=$?"
echo "FIX_RESULT=$(awk -F '\t' -v c="$CODE" '$2 == c { r = $4 } END { print r }' "$OUT"/*_03_fix_*/changes.log 2>/dev/null)"
awk -F '\t' -v c="$CODE" '$2 == c && $4 != "APPLIED" { print "  FIXDETAIL: " substr($5, 1, 300) }' "$OUT"/*_03_fix_*/changes.log 2>/dev/null
echo "FIX_RECHECK=$(status_of "$CODE")"
$TEST >/dev/null 2>&1
echo "FIX_SYNTAX_RC=$?"
snap conf > /tmp/case.postfix
if cmp -s /tmp/case.prefix /tmp/case.postfix; then echo "FIX_STATE=same"; else echo "FIX_STATE=diff"; fi
if ls -d "$OUT"/*_03_fix_* >/dev/null 2>&1; then
    sh 03_web/fix.sh -o "$OUT" --rollback "$(ls -d "$OUT"/*_03_fix_* | head -n 1)" >/dev/null 2>&1 < /dev/null
fi
snap conf > /tmp/case.rolled
if cmp -s /tmp/case.prefix /tmp/case.rolled; then echo "ROLLBACK=same"
else echo "ROLLBACK=diff"; diff /tmp/case.prefix /tmp/case.rolled | grep '^[<>]' | head -n 8 | sed 's/^/  DIFF: /'; fi

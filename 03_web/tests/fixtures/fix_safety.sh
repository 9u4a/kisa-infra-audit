#!/bin/sh
# 03_web/tests/fixtures/fix_safety.sh <engine> <apply|confirm|backupfail> [항목 목록]
#   engine: apache | apache-debian | apache-debian-opts | nginx | tomcat | tomcat-etc
# 컨테이너 안에서 실행. 결과를 KEY=VALUE 줄로 출력하고 판정은 run_tests.sh 가 한다.
#   apply      : 취약 상태 → fix.sh --apply --yes(비대화형이라 confirm 등급은 건너뜀) → 설정 문법 검사 → --rollback
#                → 설정 폴더 전체(파일 내용·권한·소유자·심볼릭 링크)가 조치 전과 같은지
#   confirm    : apply 와 같되 confirm 등급에도 y 로 답한다(script 로 가상 터미널을 만들어 /dev/tty 에 y 공급).
#                [항목 목록](콤마)만 대상으로 한다 - 비밀번호 입력이 필요한 WEB-02 등은 넣지 않는다.
#   backupfail : 백업 공간 부족(작은 tmpfs) → 백업 실패 시 설정을 바꾸지 않고 중단하는지
# 출력: FIX_RC / BASE_SYNTAX_RC(조치 전) / SYNTAX_RC(조치 후) / APPLIED_CODES / FAILED_CODES(재검증 실패·원복된 항목) /
#       NOT_ROLLED_BACK(원복 못 한 건수) / ROLLBACK=same|diff. 문법 검사: Apache httpd -t·apache2ctl -t, nginx -t,
#       Tomcat catalina.sh configtest(임시 CATALINA_BASE 에 conf 만 링크 - 실제 logs/work 를 건드리지 않게).
# engine 변형(1.3.3, KNOWN_ISSUES F-R4/F-R5):
#   apache-debian      : Debian 12 apache2 패키지 레이아웃(sites-enabled 의 Options Indexes, mods-enabled 의 dav 링크)
#   apache-debian-opts : 위 + Options All / +IncludesNOEXEC +FollowSymLinks / IncludesNOEXEC 를 쓰는 <Directory>(WEB-04/12/19 조치 대상)
#   tomcat-etc         : tomcat:10 의 conf 를 /etc/tomcat10 로 옮겨 tomcat_home 에 conf/ 가 없는 배치(조치가 진단과 같은
#                        tomcat_conf_dir 를 쓰는지)
set -u
ENGINE=$1
MODE=$2
ITEMS=${3:-}
OUT=${FIX_OUT:-/tmp/fixout}

case "$ENGINE" in
    apache) SETUP=apache; RUN_E=apache; DIRS="/usr/local/apache2/conf /usr/local/apache2/logs"; TEST="httpd -t" ;;
    apache-debian|apache-debian-opts) SETUP=apache-debian; RUN_E=apache; DIRS="/etc/apache2 /var/log/apache2"; TEST="apache2ctl -t" ;;
    nginx) SETUP=nginx; RUN_E=nginx; DIRS="/etc/nginx /var/log/nginx /usr/share/nginx"; TEST="nginx -t" ;;
    tomcat) SETUP=tomcat; RUN_E=tomcat; TC_CONF=/usr/local/tomcat/conf; TEST=tc_test
            DIRS="/usr/local/tomcat/conf /usr/local/tomcat/logs /usr/local/tomcat/webapps" ;;
    tomcat-etc) SETUP=tomcat; RUN_E=tomcat; TC_CONF=/etc/tomcat10; TEST=tc_test
            DIRS="/etc/tomcat10 /usr/local/tomcat/logs /usr/local/tomcat/webapps" ;;
    *) echo "usage: fix_safety.sh <apache|apache-debian|apache-debian-opts|nginx|tomcat|tomcat-etc> <apply|confirm|backupfail> [items]" >&2; exit 2 ;;
esac

# tc_test -> Tomcat 설정 검사(catalina.sh configtest, 실패 시 0 이 아닌 값)
tc_test() {
    mkdir -p /tmp/kisa_cb/logs /tmp/kisa_cb/temp /tmp/kisa_cb/work
    ln -sfn "$TC_CONF" /tmp/kisa_cb/conf
    CATALINA_BASE=/tmp/kisa_cb /usr/local/tomcat/bin/catalina.sh configtest
}

sh 03_web/tests/fixtures/setup.sh "$SETUP" vuln >/dev/null 2>&1
case "$ENGINE" in
    apache-debian-opts)
        # 서로 다른 형태 세 가지: 무표기 All, 부호 있는 +IncludesNOEXEC·+FollowSymLinks(+All 은 Apache 가 거부), 무표기 IncludesNOEXEC
        mkdir -p /var/www/html/a /var/www/html/b /var/www/html/c
        sed -i 's#^</VirtualHost>#\t<Directory /var/www/html/a>\n\t\tOptions All MultiViews\n\t</Directory>\n\t<Directory /var/www/html/b>\n\t\tOptions +IncludesNOEXEC +FollowSymLinks -ExecCGI\n\t</Directory>\n\t<Directory /var/www/html/c>\n\t\tOptions IncludesNOEXEC\n\t</Directory>\n</VirtualHost>#' \
            /etc/apache2/sites-available/000-default.conf
        ;;
    tomcat-etc)
        mv /usr/local/tomcat/conf /etc/tomcat10
        ;;
esac

# snap -> 대상 폴더 전체의 상태(경로·종류·권한·소유자·내용 체크섬·심볼릭 링크 대상) 목록
snap() {
    for d in $DIRS; do [ -e "$d" ] && find "$d" -print 2>/dev/null; done | LC_ALL=C sort | while IFS= read -r p; do
        if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
        elif [ -f "$p" ]; then printf 'F %s %s %s\n' "$p" "$(stat -c '%a %u %g' "$p")" "$(cksum < "$p")"
        else printf 'D %s %s\n' "$p" "$(stat -c '%a %u %g' "$p")"; fi
    done
}

sh 03_web/run.sh -e "$RUN_E" -o /tmp/runout >/dev/null 2>&1
R=$(ls /tmp/runout/*/result.json)
$TEST >/dev/null 2>&1
echo "BASE_SYNTAX_RC=$?"
snap > /tmp/snap.before

# codes <결과> -> changes.log(시각<TAB>코드<TAB>등급<TAB>결과<TAB>상세) 에서 그 결과인 항목 코드(콤마 구분)
codes() { awk -F '\t' -v r="$1" '$4 ~ r { print $2 }' "$OUT"/*_03_fix_*/changes.log 2>/dev/null | sort -u | paste -sd, -; }

report() {
    $TEST >/dev/null 2>&1
    echo "SYNTAX_RC=$?"
    echo "APPLIED_CODES=$(codes '^APPLIED$')"
    echo "FAILED_CODES=$(codes '^FAILED_')"
    echo "NOT_ROLLED_BACK=$(awk -F '\t' '$4 == "FAILED_NOT_ROLLED_BACK"' "$OUT"/*_03_fix_*/changes.log 2>/dev/null | wc -l | tr -d ' ')"
    awk -F '\t' '$4 ~ /^FAILED_/ { print "  FAILDETAIL: " $2 " " substr($5, 1, 300) }' "$OUT"/*_03_fix_*/changes.log 2>/dev/null
    sh 03_web/fix.sh -o "$OUT" --rollback "$(ls -d "$OUT"/*_03_fix_*)" >/dev/null 2>&1 < /dev/null
    snap > /tmp/snap.after
    if cmp -s /tmp/snap.before /tmp/snap.after; then echo "ROLLBACK=same"
    else echo "ROLLBACK=diff"; diff /tmp/snap.before /tmp/snap.after | grep '^[<>]' | head -n 10 | sed 's/^/  DIFF: /'; fi
}

case "$MODE" in
    apply)
        # shellcheck disable=SC2086
        sh 03_web/fix.sh -r "$R" -o "$OUT" ${ITEMS:+-i "$ITEMS"} --apply --yes > /tmp/fix.log 2>&1 < /dev/null
        echo "FIX_RC=$?"
        report
        ;;
    confirm)
        command -v script >/dev/null 2>&1 || { echo "SCRIPT=missing"; exit 0; }
        # script 가 만든 가상 터미널이 fix.sh 의 /dev/tty 가 되고, 아래 반복문의 y 가 그 터미널 입력으로 들어간다.
        # yes 처럼 쉬지 않고 쓰면 터미널 에코가 로그를 채우므로 천천히 쓰고, script 가 끝나면 SIGPIPE 로 멈춘다.
        (while echo y; do sleep 0.3; done) 2>/dev/null | \
            script -qec "sh 03_web/fix.sh -r '$R' -o '$OUT' ${ITEMS:+-i '$ITEMS'} --apply --yes" /dev/null > /tmp/fix.log 2>&1
        echo "FIX_RC=$?"
        report
        ;;
    backupfail)
        sh 03_web/fix.sh -r "$R" -o "$OUT" -i WEB-04 --apply --yes > /tmp/fix.log 2>&1 < /dev/null
        echo "FIX_RC=$?"
        snap > /tmp/snap.after
        cmp -s /tmp/snap.before /tmp/snap.after && echo "CONF=unchanged" || echo "CONF=changed"
        echo "ABORTED=$(grep -c ABORTED "$OUT"/*_03_fix_*/changes.log 2>/dev/null)"
        ;;
esac

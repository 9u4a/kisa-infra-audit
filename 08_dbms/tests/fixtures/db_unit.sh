#!/bin/sh
# 08_dbms/tests/fixtures/db_unit.sh <mysql|postgres> — DB 서버 없이 클라이언트 이미지 안에서 도는 lib/common_db.sh 단위 검사
# (run_tests.sh 가 docker run --rm 으로 호출, root). 컨테이너 안의 파일·프로세스를 바꾸므로 운영 서버에서 실행 금지.
#  - B4: _db_run 은 TERM 을 무시하는 클라이언트도 제한 시간 + 5초 안에 끝내야 한다(timeout -k, S2)
#  - A17(mysql): --defaults-file 로 띄운 mysqld 는 그 파일(과 !include 파일)만 읽는다 - D-14 는 그 파일들로 판정해야 한다
set -u
cd /infra || exit 2
LIB_DIR=/infra/lib
# shellcheck disable=SC1091
. "$LIB_DIR/common.sh"
ENGINE=$1
fail=0
ok() { echo "  ok   $*"; }
ng() { echo "  FAIL $*"; fail=1; }

# ---- B4: _db_run 종료 신호 무시 ----------------------------------------------------------------------
t0=$(date +%s)
DB_CMD_TIMEOUT=2 _db_run sh -c 'trap "" TERM; sleep 40; :' 2>/dev/null
rc=$?
dt=$(( $(date +%s) - t0 ))
if [ "$dt" -le 15 ] && [ "$rc" -ne 0 ]; then
    ok "_db_run: TERM 무시 명령을 ${dt}초 만에 중단(rc=$rc)"
else
    ng "_db_run: TERM 무시 명령에 ${dt}초 대기(rc=$rc) - timeout -k 없음(무기한 대기 가능, B4)"
fi

# ---- A17: --defaults-file 로 띄운 mysqld ------------------------------------------------------------
if [ "$ENGINE" = "mysql" ]; then
    u=/tmp/kisa_unit; mkdir -p "$u"
    printf '[mysqld]\n!include %s/extra.cnf\n' "$u" > "$u/my.cnf"; chmod 640 "$u/my.cnf"
    printf '[mysqld]\n' > "$u/extra.cnf"; chmod 646 "$u/extra.cnf"
    # 기본 경로의 /etc/my.cnf 는 기준 충족(640 root:mysql)으로 둔다 - 예전 D-14 는 이 파일만 보고 GOOD 이었다
    chmod 640 /etc/my.cnf; chgrp mysql /etc/my.cnf
    # 실행 파일 이름(comm)이 mysqld 인 가짜 프로세스(명령행에 --defaults-file) - 클라이언트 이미지에는 mysqld 가 돌지 않는다
    cp /bin/sh "$u/mysqld"
    "$u/mysqld" -c 'sleep 60; :' "--defaults-file=$u/my.cnf" &
    fake=$!
    sleep 1
    files=$(mysql_config_files)
    if printf '%s\n' "$files" | grep -qx "$u/my.cnf" && printf '%s\n' "$files" | grep -qx "$u/extra.cnf" \
        && ! printf '%s\n' "$files" | grep -qx /etc/my.cnf; then
        ok "mysql_config_files: --defaults-file·!include 만 반환($(printf '%s' "$files" | tr '\n' ' '))"
    else
        ng "mysql_config_files: --defaults-file 반영 안 됨 - $(printf '%s' "$files" | tr '\n' ' ')"
    fi
    out=$(mktemp -d)
    sh 08_dbms/run.sh -e mysql -i D-14 -o "$out" >/dev/null 2>&1
    st=$(sed -n 's/.*"code": *"D-14", *"status": *"\([A-Z]*\)".*/\1/p' "$out"/*/result.json 2>/dev/null | head -n 1)
    if [ "$st" = "VULN" ]; then ok "D-14 = VULN(--defaults-file 의 !include 파일 646)"; else ng "D-14 기대=VULN 실제=${st:-(없음)}"; fi
    kill "$fake" 2>/dev/null
    rm -rf "$u" "$out"
fi
exit $fail

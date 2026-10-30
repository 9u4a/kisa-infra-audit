#!/bin/sh
# 03_web/tests/fixtures/cases/case_lib.sh — 항목별 케이스 파일(cases/<engine>/<코드>_<이름>.sh)이 source 하는 도우미.
# 케이스는 run_case.sh 가 set -e 서브셸에서 실행한다. "!" 로 뒤집은 명령이나 && 왼쪽은 set -e 로 멈추지 않으므로
# 상태 확인은 반드시 assert / assert_not 으로 한다(설정이 실제로 바뀌었는지 케이스 스스로 확인).

assert() { "$@" || { echo "ASSERT FAIL: $*"; exit 1; }; }
assert_not() { if "$@"; then echo "ASSERT FAIL(not): $*"; exit 1; fi; }

# wait_until <초> <명령...> -> 명령이 성공할 때까지 0.2초 간격으로 기다림(시간 초과 시 실패)
wait_until() {
    _wu_n=$(($1 * 5)); shift
    while [ "$_wu_n" -gt 0 ]; do
        "$@" && return 0
        _wu_n=$((_wu_n - 1)); sleep 0.2
    done
    echo "TIMEOUT: $*"; return 1
}

# procs_uids <comm> -> 그 이름의 프로세스 uid 목록(줄바꿈)
procs_uids() {
    for _p in /proc/[0-9]*; do
        _c=""; { IFS= read -r _c < "$_p/comm"; } 2>/dev/null
        [ "$_c" = "$1" ] && awk '/^Uid:/ { print $2 }' "$_p/status" 2>/dev/null
    done
}
# has_nonroot <comm> / all_root <comm> -> 그 이름의 프로세스 중 root 아닌 것이 있음 / 있고 전부 root
has_nonroot() { procs_uids "$1" | grep -qv '^0$'; }
all_root() { [ -n "$(procs_uids "$1")" ] && ! procs_uids "$1" | grep -qv '^0$'; }

# tomcat_uids -> Tomcat(Bootstrap) java 프로세스 uid 목록
tomcat_uids() {
    for _p in /proc/[0-9]*; do
        _c=""; { IFS= read -r _c < "$_p/comm"; } 2>/dev/null
        [ "$_c" = java ] || continue
        tr '\000' '\n' < "$_p/cmdline" 2>/dev/null | grep -qx 'org\.apache\.catalina\.startup\.Bootstrap' && \
            awk '/^Uid:/ { print $2 }' "$_p/status" 2>/dev/null
    done
}

# fake_proc <comm> -> /tmp 에 그 이름으로 복사한 sleep 을 root 로 띄운다(실제 엔진이 root 전용으로 뜨지 않는 경우의 재현용)
fake_proc() {
    mkdir -p /tmp/kisa_fake
    cp /bin/sleep "/tmp/kisa_fake/$1"
    "/tmp/kisa_fake/$1" 600 >/dev/null 2>&1 &
    wait_until 5 all_root "$1"
}

# self_signed <crt> <key> -> 테스트용 자체 서명 인증서(openssl 이 있는 이미지에서만)
self_signed() {
    openssl req -x509 -nodes -newkey rsa:2048 -days 2 -subj /CN=www.example.com -keyout "$2" -out "$1" >/dev/null 2>&1
}

# (넣을 내용은 환경변수로 넘겨 awk -v 의 \ 이스케이프 해석을 피한다 - nginx 정규식 \.php$ 등)
# insert_before_last <파일> <넣을 내용(여러 줄 가능)> -> 파일의 마지막 "}" 줄(블록 끝) 앞에 넣는다
insert_before_last() {
    CASE_INS=$2 awk 'BEGIN { ins = ENVIRON["CASE_INS"] } { l[NR] = $0 } END { for (i = NR; i >= 1; i--) if (l[i] ~ /^[ \t]*}[ \t]*$/) { k = i; break }
        for (i = 1; i <= NR; i++) { if (i == k) print ins; print l[i] } }' "$1" > "$1.case_tmp" && cat "$1.case_tmp" > "$1" && rm -f "$1.case_tmp"
}

# insert_before <파일> <고정 문자열이 든 줄> <넣을 내용> -> 그 문자열이 처음 나오는 줄 앞에 넣는다
insert_before() {
    CASE_PAT=$2 CASE_INS=$3 awk 'BEGIN { pat = ENVIRON["CASE_PAT"]; ins = ENVIRON["CASE_INS"] } !d && index($0, pat) { print ins; d = 1 } { print }' "$1" > "$1.case_tmp" && cat "$1.case_tmp" > "$1" && rm -f "$1.case_tmp"
}
# insert_after <파일> <고정 문자열이 든 줄> <넣을 내용>
insert_after() {
    CASE_PAT=$2 CASE_INS=$3 awk 'BEGIN { pat = ENVIRON["CASE_PAT"]; ins = ENVIRON["CASE_INS"] } { print } !d && index($0, pat) { print ins; d = 1 }' "$1" > "$1.case_tmp" && cat "$1.case_tmp" > "$1" && rm -f "$1.case_tmp"
}

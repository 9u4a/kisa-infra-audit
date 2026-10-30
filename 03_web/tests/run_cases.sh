#!/bin/sh
# 03_web/tests/run_cases.sh — 항목별 양방향 케이스(fixtures/cases/cases.json 의 apache/apache-debian/nginx/tomcat 줄) 실행.
# 저장소 루트에서: sh 03_web/tests/run_cases.sh   (run_tests.sh 가 이미지 빌드 후 마지막에 호출한다)
#
# 전역 vuln/hardened 픽스처(run_tests.sh)는 한 이미지에 상태를 몰아 넣어 항목 대부분이 한 방향(GOOD 또는 VULN)으로만
# 검증됐다(1.4.0 커버리지 기준선: 엔진당 양방향 1~4/26). 케이스마다 깨끗한 컨테이너를 새로 띄워 그 항목의 상태만 만들고
# (fixtures/cases/<engine>/<코드>_<이름>.sh), run_case.sh 가 ①상태가 실제로 바뀌었는지 ②진단 결과 ③VULN 케이스는 조치
# 적용→재진단→문법 검사→원복 동일성까지 확인한다(lib/tests/coverage.py 가 cases.json 을 양방향 커버리지로 센다).
# FAIL 조건: cases.json 의 케이스를 하나라도 실행하지 못함(파일 없음·결과 없음), cases/<engine>/ 에 cases.json 에 없는
# 케이스 파일이 있음, 케이스 설정 실패·상태 무변경, 기대 상태와 다름, 조치 검증 실패.
# 환경 변수: WEB_TEST_PREFIX(이미지 이름 접두어, 기본 kisa-web - 음성 대조 실험을 별도 이미지로 돌릴 때),
#            WEB_CASES_JOBS(동시 컨테이너 수, 기본 6), WEB_CASES_BUILD=1(이미지를 이 스크립트가 빌드),
#            WEB_CASES_FILTER(개발용: "엔진|코드|이름" 에 grep -E 로 거른 케이스만 - 설정 시 "전부 실행" 검사는 생략한다고 표시)
set -eu
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."

PREFIX=${WEB_TEST_PREFIX:-kisa-web}
JOBS=${WEB_CASES_JOBS:-6}
CASES_DIR=03_web/tests/fixtures/cases
ENGINES="apache apache-debian nginx tomcat"
fail=0

if [ "${WEB_CASES_BUILD:-0}" = 1 ]; then
    for e in $ENGINES; do
        docker build -q -f "03_web/tests/Dockerfile.$e" -t "$PREFIX-$e-test" . >/dev/null
    done
fi

# 대상 케이스 목록 "engine|code|name|expect"
list=$(python3 - "$CASES_DIR/cases.json" <<'PYEOF'
import json, sys
mine = {"apache", "apache-debian", "nginx", "tomcat"}
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    if c.get("engine") in mine:
        print("|".join((c["engine"], c["code"], c["name"], c["expect"])))
PYEOF
)
list=$(printf '%s\n' "$list" | tr -d '\r')   # Windows python 의 CRLF 출력 대비
total_all=$(printf '%s\n' "$list" | grep -c . || true)

# cases.json 에 있는데 케이스 파일이 없으면 실패(이미지가 예전 빌드라 안에 파일이 남아 있어도 저장소 기준으로 잡는다)
while IFS="|" read -r e c nm _; do
    [ -n "$e" ] || continue
    [ -f "$CASES_DIR/$e/${c}_$nm.sh" ] || { echo "FAIL: case/$e/${c}_$nm - 케이스 파일 없음(cases.json 의 케이스를 실행할 수 없음)"; fail=1; }
done <<EOF_LIST
$list
EOF_LIST

# cases.json 에 없는 케이스 파일(실행되지 않는 케이스)은 실패
for e in $ENGINES; do
    for f in "$CASES_DIR/$e"/*.sh; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .sh)
        printf '%s\n' "$list" | cut -d'|' -f1-3 | grep -qxF "$e|${b%%_*}|${b#*_}" || {
            echo "FAIL: case/$e/$b - cases.json 에 없는 케이스 파일(실행되지 않음)"; fail=1; }
    done
done

if [ -n "${WEB_CASES_FILTER:-}" ]; then
    list=$(printf '%s\n' "$list" | grep -E "$WEB_CASES_FILTER" || true)
    echo "[cases] WEB_CASES_FILTER='$WEB_CASES_FILTER' - $(printf '%s\n' "$list" | grep -c . || true)/$total_all 케이스만 실행(개발용, 전체 실행 검사 생략)"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/kisa_web_cases.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
start=$(date +%s)
n=0; running=0
while IFS='|' read -r eng code name expect; do
    [ -n "$eng" ] || continue
    n=$((n + 1))
    printf '%s|%s|%s|%s\n' "$eng" "$code" "$name" "$expect" > "$tmp/$n.key"
    ( docker run --rm --name "$PREFIX-case-$$-$n" "$PREFIX-$eng-test" \
        sh 03_web/tests/fixtures/cases/run_case.sh "$eng" "$code" "$name" "$expect" > "$tmp/$n.out" 2>&1 < /dev/null || true ) &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then wait; running=0; fi
done <<EOF_CASES
$list
EOF_CASES
wait

executed=0; passed=0
i=0
while [ "$i" -lt "$n" ]; do
    i=$((i + 1))
    IFS='|' read -r eng code name expect < "$tmp/$i.key"
    out=$(cat "$tmp/$i.out" 2>/dev/null || true)
    kv() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | head -n 1; }
    label="case/$eng/${code}_$name"
    st=$(kv STATUS)
    [ -n "$st" ] && executed=$((executed + 1))
    why=""
    [ "$(kv SETUP_RC)" = 0 ] || why="$why 케이스설정실패(SETUP_RC=$(kv SETUP_RC))"
    [ "$(kv CHANGED)" = yes ] || why="$why 상태무변경"
    [ "$st" = "$expect" ] || why="$why 기대=$expect 실제=${st:-없음}"
    fm=$(kv FIX_MODE)
    fixinfo=""
    case "$fm" in
        ''|n/a) ;;
        SKIP) fixinfo=" [조치 생략: $(kv FIX_WHY)]"
              [ -n "$(kv FIX_WHY)" ] || why="$why 조치SKIP사유없음" ;;
        GOOD|MANUAL)
            [ "$(kv FIX_RESULT)" = APPLIED ] || why="$why 조치결과=$(kv FIX_RESULT)(기대 APPLIED)"
            [ "$(kv FIX_RECHECK)" = "$fm" ] || why="$why 조치후재진단=$(kv FIX_RECHECK)(기대 $fm)"
            [ "$(kv BASE_SYNTAX_RC)" = 0 ] || why="$why 조치전문법실패"
            [ "$(kv FIX_SYNTAX_RC)" = 0 ] || why="$why 조치후문법실패"
            [ "$(kv FIX_STATE)" = diff ] || why="$why 조치가설정을바꾸지않음"
            [ "$(kv ROLLBACK)" = same ] || why="$why 원복후상태다름"
            fixinfo=" [조치 $(kv FIX_RESULT)→$(kv FIX_RECHECK), 원복 $(kv ROLLBACK)]" ;;
        NONE)
            [ "$(kv FIX_RESULT)" != APPLIED ] || why="$why 조치가적용됨(기대: 미적용)"
            [ "$(kv FIX_STATE)" = same ] || why="$why 미적용조치가설정을바꿈"
            [ "$(kv FIX_RECHECK)" = VULN ] || why="$why 미적용후재진단=$(kv FIX_RECHECK)"
            [ "$(kv ROLLBACK)" = same ] || why="$why 원복후상태다름"
            fixinfo=" [조치 미적용 기대: $(kv FIX_RESULT), 설정 $(kv FIX_STATE)]" ;;
        *) why="$why 알수없는FIX지시($fm)" ;;
    esac
    if [ -z "$why" ]; then
        passed=$((passed + 1))
        echo "PASS: $label = $st$fixinfo"
    else
        echo "FAIL: $label -$why"
        printf '%s\n' "$out" | sed 's/^/    /' | tail -n 30
        fail=1
    fi
done
if [ -z "${WEB_CASES_FILTER:-}" ] && { [ "$n" -ne "$total_all" ] || [ "$executed" -ne "$total_all" ]; }; then
    echo "FAIL: cases - cases.json 의 케이스 $total_all 건 중 $executed 건만 실행됨"
    fail=1
fi
echo "[cases] $passed/$n 통과, 실행 $executed 건, $(( $(date +%s) - start ))초 (동시 $JOBS)"
exit $fail

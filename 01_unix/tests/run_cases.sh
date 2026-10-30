#!/bin/sh
# 01_unix/tests/run_cases.sh — 항목별 양방향 케이스(fixtures/cases/cases.json) 실행기(1.4.0). run_tests.sh 가 부른다.
# 저장소 루트에서 실행: sh 01_unix/tests/run_cases.sh
#
# 케이스마다 새 컨테이너(Dockerfile.cases, systemd PID 1)를 띄워 fixtures/cases/case_run.sh 를 실행한다 - 케이스끼리
# 상태가 섞이지 않게 하고, 서비스 항목은 실제 systemctl 경로로 판정·조치·원복한다. 병렬 실행(CASE_JOBS, 기본 6).
# 실패 조건:
#   - cases.json 의 케이스가 실행되지 않았거나(결과 없음) cases.sh 에 준비 함수가 없음
#   - 준비가 상태를 바꾸지 않음(CHANGED=no) - 준비가 조용히 실패하면 "기본 상태의 판정"을 케이스 판정으로 착각한다
#   - 판정(STATUS)이 기대(expect)와 다름
#   - VULN 케이스의 조치 검증(fix 필드): GOOD/MANUAL = fix.sh 결과 APPLIED 이고 재검증이 그 값, NOFIX = 자동 조치 불가로
#     변경 없이 끝남(FAILED_ROLLED_BACK/SKIPPED). 어느 쪽이든 --rollback 뒤 상태가 케이스 준비 직후와 같아야 함(ROLLBACK=same)
# systemd 컨테이너는 --privileged 없이 띄운다(cgroup 만 쓰기 가능하게 마운트).
set -u
export MSYS_NO_PATHCONV=1

if [ "${1:-}" = "--one" ]; then
    # --one <출력 디렉터리> <코드> <이름> <base> <fix> — 케이스 1개(병렬 실행 단위)
    out=$2; code=$3; name=$4; base=$5; fx=$6
    cname="kisa-u01-case-$$-$code-$name"
    docker rm -f "$cname" >/dev/null 2>&1
    if ! docker run -d --name "$cname" --tmpfs /run --tmpfs /run/lock --cgroupns=host \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw kisa-u01-cases >/dev/null 2>"$out/$code.$name.err"; then
        echo "BOOT=fail" > "$out/$code.$name.out"; exit 0
    fi
    i=0
    while [ "$i" -lt 60 ]; do
        s=$(docker exec "$cname" systemctl is-system-running 2>/dev/null)
        case "$s" in running|degraded) break ;; esac
        i=$((i + 1)); sleep 1
    done
    docker exec "$cname" sh 01_unix/tests/fixtures/cases/case_run.sh "$code" "$name" "$base" "$fx" > "$out/$code.$name.out" 2>"$out/$code.$name.err"
    docker rm -f "$cname" >/dev/null 2>&1
    exit 0
fi

cd "$(dirname "$0")/../.." || exit 2
CASES=01_unix/tests/fixtures/cases/cases.json
docker build -q -f 01_unix/tests/Dockerfile.cases -t kisa-u01-cases . >/dev/null || { echo "FAIL: cases - 이미지 빌드 실패"; exit 1; }

# cases.json → "코드 이름 base fix expect" 줄(기본값: base=hardened, fix 는 VULN 이면 GOOD, 아니면 -)
LIST=$(python3 - "$CASES" <<'PYEOF'
import json, sys
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    fx = c.get("fix") or ("GOOD" if c["expect"] == "VULN" else "-")
    print(c["code"], c["name"], c.get("base", "hardened"), fx, c["expect"])
PYEOF
)
LIST=$(printf '%s\n' "$LIST" | tr -d '\r')   # Windows 의 python 은 줄 끝에 CR 을 붙인다
[ -n "$LIST" ] || { echo "FAIL: cases - cases.json 을 읽지 못함"; exit 1; }
OUT=$(mktemp -d 2>/dev/null || echo "/tmp/kisa_u01_cases_$$")
mkdir -p "$OUT"
start=$(date +%s)
printf '%s\n' "$LIST" | awk '{ print $1, $2, $3, $4 }' | \
    xargs -P "${CASE_JOBS:-6}" -n 4 sh "01_unix/tests/run_cases.sh" --one "$OUT"
elapsed=$(( $(date +%s) - start ))

fail=0; n=0; nfix=0
while read -r code name base fx expect; do
    [ -n "$code" ] || continue
    n=$((n + 1))
    f="$OUT/$code.$name.out"
    kv() { sed -n "s/^$1=//p" "$f" 2>/dev/null | head -n1; }
    why=""
    if [ ! -s "$f" ]; then
        why=" 실행되지 않음(결과 없음: $(head -c 200 "$OUT/$code.$name.err" 2>/dev/null | tr '\n' ' '))"
    else
        [ "$(kv CASE_FN)" = ok ] || why="$why 준비함수($(kv CASE_FN))"
        [ "$(kv CHANGED)" = yes ] || why="$why 준비가 상태를 바꾸지 않음(CHANGED=$(kv CHANGED))"
        [ "$(kv STATUS)" = "$expect" ] || why="$why 판정(기대=$expect 실제=$(kv STATUS): $(kv DETAIL))"
        if [ "$fx" != "-" ]; then
            nfix=$((nfix + 1))
            fr=$(kv FIX)
            case "$fx" in
                GOOD|MANUAL) [ "$fr" = "APPLIED/$fx" ] || why="$why 조치(기대=APPLIED/$fx 실제=$fr $(kv FIXDETAIL))" ;;
                NOFIX) case "$fr" in FAILED_ROLLED_BACK/*|SKIPPED/*|MANUAL/*) : ;; *) why="$why 조치(기대=변경 없이 실패 실제=$fr)" ;; esac ;;
            esac
            [ "$(kv ROLLBACK)" = same ] || why="$why 원복후상태다름($(sed -n 's/^DIFF=//p' "$f" | head -n 6 | tr '\n' ';'))"
        fi
    fi
    if [ -z "$why" ]; then
        echo "PASS: case $code/$name (STATUS=$expect$( [ "$fx" != "-" ] && printf ' FIX=%s ROLLBACK=same' "$(kv FIX)"))"
    else
        echo "FAIL: case $code/$name -$why"; fail=1
    fi
done <<EOF
$LIST
EOF
echo "cases: ${n}건(조치 검증 ${nfix}건), ${elapsed}초"
rm -rf "$OUT"
exit $fail

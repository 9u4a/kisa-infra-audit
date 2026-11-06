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
#   - result.json 이 올바른 UTF-8 이 아님(iconv 가 있을 때), "secret" 필드 값이 결과물에 남음(조치 백업 폴더 제외)
#   - VULN 케이스의 조치 검증(fix 필드): GOOD/MANUAL = fix.sh 결과 APPLIED 이고 재검증이 그 값, PARTIAL = 일부만 자동 조치
#     (PARTIAL_MANUAL), NOFIX = 자동 조치 불가로
#     변경 없이 끝남(FAILED_ROLLED_BACK/SKIPPED). 어느 쪽이든 --rollback 뒤 상태가 케이스 준비 직후와 같아야 함(ROLLBACK=same)
# systemd 컨테이너는 --privileged 없이 띄운다(cgroup 만 쓰기 가능하게 마운트).
# CASE_DISTRO=debian(기본, Dockerfile.cases) | rhel(Dockerfile.cases.rhel, Rocky Linux 9 - 1.5.0 C1). 같은 cases.json 을 쓰고
# 케이스의 "distro" 필드(목록)가 있으면 그 배포판에서만 실행한다(배포판 고유 경로를 다루는 케이스).
# CASE_ONLY='U-37 U-28/nft-invalid-only' 처럼 주면 그 코드(또는 코드/이름) 케이스만 실행한다(개발 중 부분 실행용).
# 케이스의 "secret" 필드가 있으면 그 문자열이 진단·조치 결과물 어디에도 없어야 한다(S5 - 1.5.0 C3).
set -u
export MSYS_NO_PATHCONV=1
CASE_DISTRO=${CASE_DISTRO:-debian}
case "$CASE_DISTRO" in
    debian) IMG=kisa-u01-cases; DOCKERFILE=01_unix/tests/Dockerfile.cases ;;
    rhel) IMG=kisa-u01-cases-rhel; DOCKERFILE=01_unix/tests/Dockerfile.cases.rhel ;;
    *) echo "FAIL: cases - 알 수 없는 CASE_DISTRO=$CASE_DISTRO (debian|rhel)"; exit 2 ;;
esac
# CASE_IMG_SUFFIX: 같은 호스트에서 여러 작업이 동시에 케이스를 돌릴 때 이미지 태그가 서로 덮어쓰지 않게 붙이는 접미어
IMG="$IMG${CASE_IMG_SUFFIX:-}"
export CASE_DISTRO

if [ "${1:-}" = "--one" ]; then
    # --one <출력 디렉터리> <코드> <이름> <base> <fix> <secret> — 케이스 1개(병렬 실행 단위)
    out=$2; code=$3; name=$4; base=$5; fx=$6; secret=$7
    cname="kisa-u01-case-$CASE_DISTRO-$$-$code-$name"
    docker rm -f "$cname" >/dev/null 2>&1
    if ! docker run -d --name "$cname" --tmpfs /run --tmpfs /run/lock --cgroupns=host \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw "$IMG" >/dev/null 2>"$out/$code.$name.err"; then
        echo "BOOT=fail" > "$out/$code.$name.out"; exit 0
    fi
    i=0
    while [ "$i" -lt 60 ]; do
        s=$(docker exec "$cname" systemctl is-system-running 2>/dev/null)
        case "$s" in running|degraded) break ;; esac
        i=$((i + 1)); sleep 1
    done
    docker exec -e CASE_ENV="$CASE_DISTRO" "$cname" sh 01_unix/tests/fixtures/cases/case_run.sh "$code" "$name" "$base" "$fx" "$secret" > "$out/$code.$name.out" 2>"$out/$code.$name.err"
    docker rm -f "$cname" >/dev/null 2>&1
    exit 0
fi

cd "$(dirname "$0")/../.." || exit 2
CASES=01_unix/tests/fixtures/cases/cases.json
docker build -q -f "$DOCKERFILE" -t "$IMG" . >/dev/null || { echo "FAIL: cases($CASE_DISTRO) - 이미지 빌드 실패"; exit 1; }

# cases.json → "코드 이름 base fix expect" 줄(기본값: base=hardened, fix 는 VULN 이면 GOOD, 아니면 -)
LIST=$(python3 - "$CASES" "$CASE_DISTRO" "${CASE_ONLY:-}" <<'PYEOF'
import json, sys
only = sys.argv[3].split()
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    if sys.argv[2] not in c.get("distro", ["debian", "rhel"]):
        continue
    if only and c["code"] not in only and f'{c["code"]}/{c["name"]}' not in only:
        continue
    fx = c.get("fix") or ("GOOD" if c["expect"] == "VULN" else "-")
    print(c["code"], c["name"], c.get("base", "hardened"), fx, c.get("secret", "-"), c["expect"])
PYEOF
)
LIST=$(printf '%s\n' "$LIST" | tr -d '\r')   # Windows 의 python 은 줄 끝에 CR 을 붙인다
[ -n "$LIST" ] || { echo "FAIL: cases - cases.json 을 읽지 못함"; exit 1; }
OUT=$(mktemp -d 2>/dev/null || echo "/tmp/kisa_u01_cases_$$")
mkdir -p "$OUT"
start=$(date +%s)
printf '%s\n' "$LIST" | awk '{ print $1, $2, $3, $4, $5 }' | \
    xargs -P "${CASE_JOBS:-6}" -n 5 sh "01_unix/tests/run_cases.sh" --one "$OUT"
elapsed=$(( $(date +%s) - start ))

fail=0; n=0; nfix=0
while read -r code name base fx secret expect; do
    [ -n "$code" ] || continue
    n=$((n + 1))
    f="$OUT/$code.$name.out"
    kv() { sed -n "s/^$1=//p" "$f" 2>/dev/null | head -n1; }
    why=""
    if [ ! -s "$f" ]; then
        why=" 실행되지 않음(결과 없음: $(head -c 200 "$OUT/$code.$name.err" 2>/dev/null | tr '\n' ' '))"
    else
        [ "$(kv CASE_FN)" = ok ] || why="$why 준비함수($(kv CASE_FN))"
        [ "$(kv SETUP_RC)" = 0 ] || why="$why 준비실패(SETUP_RC=$(kv SETUP_RC))"
        [ "$(kv CHANGED)" = yes ] || why="$why 준비가 상태를 바꾸지 않음(CHANGED=$(kv CHANGED))"
        [ "$(kv STATUS)" = "$expect" ] || why="$why 판정(기대=$expect 실제=$(kv STATUS): $(kv DETAIL))"
        [ "$(kv UTF8)" != bad ] || why="$why result.json 이 올바른 UTF-8 이 아님"
        if [ "$secret" != "-" ]; then
            [ "$(kv LEAK)" = no ] || why="$why 비밀값이 결과물에 남음(LEAK=$(kv LEAK))"
        fi
        if [ "$fx" != "-" ]; then
            nfix=$((nfix + 1))
            fr=$(kv FIX)
            case "$fx" in
                GOOD|MANUAL) [ "$fr" = "APPLIED/$fx" ] || why="$why 조치(기대=APPLIED/$fx 실제=$fr $(kv FIXDETAIL))" ;;
                NOFIX) case "$fr" in FAILED_ROLLED_BACK/*|SKIPPED/*|MANUAL/*) : ;; *) why="$why 조치(기대=변경 없이 실패 실제=$fr)" ;; esac ;;
                PARTIAL) case "$fr" in PARTIAL_MANUAL/*) : ;; *) why="$why 조치(기대=PARTIAL_MANUAL 실제=$fr $(kv FIXDETAIL))" ;; esac ;;
            esac
            [ "$(kv ROLLBACK)" = same ] || why="$why 원복후상태다름($(sed -n 's/^DIFF=//p' "$f" | head -n 6 | tr '\n' ';'))"
        fi
    fi
    if [ -z "$why" ]; then
        echo "PASS: case[$CASE_DISTRO] $code/$name (STATUS=$expect$( [ "$fx" != "-" ] && printf ' FIX=%s ROLLBACK=same' "$(kv FIX)"))"
    else
        echo "FAIL: case[$CASE_DISTRO] $code/$name -$why"; fail=1
    fi
done <<EOF
$LIST
EOF
echo "cases($CASE_DISTRO): ${n}건(조치 검증 ${nfix}건), ${elapsed}초"
rm -rf "$OUT"
exit $fail

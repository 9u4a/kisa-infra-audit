#!/bin/sh
# audit.sh — 통합 런처 (POSIX sh, Unix 계열 호스트용).
#
# 이 호스트에 적용되는 모든 카테고리를 한 번에 진단한다: 01_unix(항상) + 03_web(엔진 자동 감지,
# 미감지 시에도 안전하게 전 항목 NA로 끝남) + 08_dbms(엔진 자동 감지, 감지 실패/모호 시 건너뜀).
# 각 카테고리의 개별 옵션(-i/-g 등 세부 항목 지정)은 지원하지 않는다 - 특정 항목만 보려면 해당
# 카테고리의 run.sh를 직접 실행할 것. 이 스크립트도 다른 run.*과 동일하게 대상 설정을 변경하지
# 않는다(진단 전용) - 조치는 카테고리별 fix.*를 참고.
#
# 사용법:
#   audit.sh                 적용 가능한 모든 카테고리 진단
#   audit.sh -e mysql        08_dbms 엔진 수동 지정 (자동 감지 실패/모호 시)
#   audit.sh -o <dir>        결과 출력 경로 지정 (기본: ./output)
#   audit.sh -h               도움말
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_BASE="$SCRIPT_DIR/output"
DBMS_ENGINE=""

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts "e:o:h" opt; do
    case "$opt" in
        e) DBMS_ENGINE=$OPTARG ;;
        o) OUT_BASE=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

HOST=$(hostname 2>/dev/null || echo unknown)
TS=$(date +%Y%m%d-%H%M%S)
RUN_LOG_DIR="$OUT_BASE/${HOST}_audit_${TS}"
mkdir -p "$RUN_LOG_DIR"

echo "=== 주요정보통신기반시설 통합 진단 ==="
echo "호스트     : $HOST"
echo "결과 경로  : $OUT_BASE"
echo "통합 로그  : $RUN_LOG_DIR"
echo "----------------------------------------------------------------------"

UNIX_DIR=""
WEB_DIR=""
DBMS_DIR=""

echo "[1/3] 01_unix 진단 중..."
sh "$SCRIPT_DIR/01_unix/run.sh" -o "$OUT_BASE" | tee "$RUN_LOG_DIR/01_unix.log"
UNIX_DIR=$(grep "결과 경로: " "$RUN_LOG_DIR/01_unix.log" | sed 's/.*결과 경로: //')

echo "[2/3] 03_web 진단 중... (엔진 미설치 시 전 항목 해당없음으로 끝남)"
sh "$SCRIPT_DIR/03_web/run.sh" -o "$OUT_BASE" | tee "$RUN_LOG_DIR/03_web.log"
WEB_DIR=$(grep "결과 경로: " "$RUN_LOG_DIR/03_web.log" | sed 's/.*결과 경로: //')

echo "[3/3] 08_dbms 진단 중... (구동 중인 엔진을 찾지 못하면 건너뜀)"
if sh "$SCRIPT_DIR/08_dbms/run.sh" ${DBMS_ENGINE:+-e "$DBMS_ENGINE"} -o "$OUT_BASE" > "$RUN_LOG_DIR/08_dbms.log" 2>&1; then
    cat "$RUN_LOG_DIR/08_dbms.log"
    DBMS_DIR=$(grep "결과 경로: " "$RUN_LOG_DIR/08_dbms.log" | sed 's/.*결과 경로: //')
else
    echo "  건너뜀 - 구동 중인 DBMS 엔진을 자동 감지하지 못했거나 여러 엔진이 동시에 감지되었습니다."
    echo "  (-e mysql|postgres|oracle 로 수동 지정해 다시 시도할 수 있음)"
    sed 's/^/  /' "$RUN_LOG_DIR/08_dbms.log"
fi

echo "----------------------------------------------------------------------"
echo "=== 통합 진단 요약 ==="
for d in "$UNIX_DIR" "$WEB_DIR" "$DBMS_DIR"; do
    if [ -n "$d" ] && [ -f "$d/summary.txt" ]; then
        cat "$d/summary.txt"
        echo
    fi
done
echo "카테고리별 상세 결과 경로:"
[ -n "$UNIX_DIR" ] && echo "  01_unix : $UNIX_DIR"
[ -n "$WEB_DIR" ] && echo "  03_web  : $WEB_DIR"
[ -n "$DBMS_DIR" ] && echo "  08_dbms : $DBMS_DIR"
echo "통합 로그: $RUN_LOG_DIR"

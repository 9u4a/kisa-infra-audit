#!/bin/sh
# 03_web/tests/run_tests.sh — Docker(공식 httpd:2.4/nginx:latest/tomcat:10, Debian apache2, Rocky 9 httpd·tomcat) 기반 회귀 테스트.
# 저장소 루트에서 실행: sh 03_web/tests/run_tests.sh
#
# 엔진별로 WEB-04(디렉터리 리스팅)만 명시적으로 vuln/hardened 를 가르고, 나머지 25항목은
# 각 공식 이미지의 있는 그대로의 기본값을 반영한다(완전한 전수 검증이 아님 - 01_unix와
# 동일한 범위 제한 원칙, 03_web/CLAUDE.md "테스트 커버리지" 참고). 데몬 프로세스는 띄우지
# 않고 설정 파일 판정 위주로만 검증한다.
#
# expected_<engine>_<mode>.json 은 예측값이 아니라 실제로 run.sh를 돌려 나온 결과를 고정한
# 것이다(05_network/01_unix와 동일한 방식) - 흥미롭게도 httpd:2.4는 기본값 자체가 WEB-04
# 기준 취약(vuln=기본값 그대로, hardened=명시적으로 끔)인 반면 nginx/tomcat은 기본값이
# 이미 양호(vuln=명시적으로 켬, hardened=기본값 그대로)라 세 엔진의 기본 태세가 다르다.
# 1.4.0: 전역 픽스처의 기대값은 "그 상태에 대한 가이드 판정"이다(실행 결과 고정 아님 - Tomcat WEB-11 은 기본 appBase
# 그대로라 VULN). 전역 픽스처로 한 방향만 검증되는 항목은 마지막의 run_cases.sh(항목별 케이스)가 반대 방향을 채운다.
set -eu
export MSYS_NO_PATHCONV=1   # Windows git-bash에서 docker 인자 경로 자동변환 방지(실 Linux에선 무해)

cd "$(dirname "$0")/../.."   # 저장소 루트로 이동

fail=0
# apache-debian: Debian 12 apache2 패키지 레이아웃(/etc/apache2, ServerRoot 주석, *-enabled Include) - 진단 검수 WEB-R1.
# apache-rhel/tomcat-rhel(1.5.0 C2): Rocky Linux 9 httpd·tomcat 패키지 레이아웃(KNOWN_ISSUES L-04). run.sh 에는 apache/tomcat 으로 넘긴다.
run_engine() { case "$1" in apache-debian|apache-rhel) echo apache ;; tomcat-rhel) echo tomcat ;; *) echo "$1" ;; esac; }
# 엔진 버전 matrix(1.5.0 C5): 공식 이미지 엔진의 기본 이미지와 대상 엔진을 바꿔 같은 검사를 돈다(CI engine-matrix job, 주간·수동).
#   WEB_ENGINES=tomcat TOMCAT_IMAGE=tomcat:9 sh 03_web/tests/run_tests.sh
# 버전에 따라 기본값이 달라 판정이 정당하게 바뀌는 항목은 fixtures/expected_<엔진>@<태그>_<모드>.json 을 두고(없으면 기본 파일),
# 그 차이를 가이드 판단기준으로 검토한 사유를 파일의 "_note" 에 적는다. 배포판 패키지 엔진(-debian/-rhel)은 배포판이 버전을 정한다.
WEB_ENGINES=${WEB_ENGINES:-apache nginx tomcat apache-debian apache-rhel tomcat-rhel}
HTTPD_IMAGE=${HTTPD_IMAGE:-httpd:2.4}
NGINX_IMAGE=${NGINX_IMAGE:-nginx:latest}
TOMCAT_IMAGE=${TOMCAT_IMAGE:-tomcat:10}
export WEB_ENGINES HTTPD_IMAGE NGINX_IMAGE TOMCAT_IMAGE   # run_cases.sh 가 같은 값을 쓴다
base_image() { case "$1" in apache) echo "$HTTPD_IMAGE" ;; nginx) echo "$NGINX_IMAGE" ;; tomcat) echo "$TOMCAT_IMAGE" ;; esac; }
in_engines() { case " $WEB_ENGINES " in *" $1 "*) return 0 ;; esac; return 1; }
expected_file() {  # expected_file <엔진> <모드>
    _tag=$(base_image "$1"); _tag=${_tag##*:}
    _ef="03_web/tests/fixtures/expected_${1}@${_tag}_${2}.json"
    { [ -n "$_tag" ] && [ -f "$_ef" ]; } || _ef="03_web/tests/fixtures/expected_${1}_${2}.json"
    echo "$_ef"
}
for engine in $WEB_ENGINES; do
    image="kisa-web-${engine}-test"
    run_e=$(run_engine "$engine")
    echo "[1/2] $engine 이미지 빌드..."
    docker build -q --build-arg BASE_IMAGE="$(base_image "$engine")" -f "03_web/tests/Dockerfile.$engine" -t "$image" . >/dev/null
    [ -z "$(base_image "$engine")" ] || echo "    기본 이미지: $(base_image "$engine")"
    # 배포판 패키지 엔진은 이미지 태그만으로 버전을 알 수 없다 - 이번 실행의 패키지 버전을 남긴다(README 검증 환경 표 근거)
    case "$engine" in
        apache-rhel) echo "    패키지: $(docker run --rm "$image" rpm -q httpd)" ;;
        tomcat-rhel) echo "    패키지: $(docker run --rm "$image" rpm -q tomcat)" ;;
        apache-debian) echo "    패키지: $(docker run --rm "$image" dpkg-query -W -f '${Package} ${Version}' apache2)" ;;
    esac

    for mode in vuln hardened; do
        echo "[*] $engine/$mode 픽스처 실행..."
        cid=$(docker create "$image" sh -c "
            sh 03_web/tests/fixtures/setup.sh $engine $mode >/dev/null 2>&1
            sh 03_web/run.sh -e $run_e -o /tmp/out >/dev/null 2>&1
            cp /tmp/out/*/result.json /result.json
        ")
        docker start -a "$cid" >/dev/null
        result_file="result_${engine}_${mode}.json"
        docker cp "$cid:/result.json" "$result_file" >/dev/null 2>&1
        docker rm "$cid" >/dev/null

        if [ ! -f "$result_file" ]; then
            echo "FAIL: $engine/$mode - 컨테이너에서 result.json 을 꺼내지 못함"
            fail=1
            continue
        fi

        if python3 - "$result_file" "$(expected_file "$engine" "$mode")" "$engine/$mode" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
result_path, expected_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(result_path, encoding="utf-8").read()
actual = {it["code"]: it["status"] for it in json.loads(raw)["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
# fixtures/setup.sh 가 tomcat-users.xml 에 넣은 비밀번호 원문이 결과물에 남으면 안 된다(민감정보 미저장)
if "Leak>Check" in raw or "Leak\\u003eCheck" in raw:
    failures.append("tomcat-users.xml 비밀번호 원문이 result.json 에 저장됨")
# server.xml Connector 의 keystorePass 원문(진단 검수 WEB-R9)
if "Rh9Leak-Pw" in raw:
    failures.append("ProxyPass URL 비밀번호 원문이 result.json 에 저장됨")
if "KsLeak9Pass" in raw:
    failures.append("server.xml keystorePass 원문이 result.json 에 저장됨")
if failures:
    print(f"FAIL: {label} - {len(failures)}건 불일치")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: {label}")
PYEOF
        then :; else fail=1; fi
        rm -f "$result_file"
    done
done

# ---- 조치(fix) 운영 안전 회귀 테스트 (fixtures/fix_safety.sh) -----------------------
# ① 조치 적용 후에도 설정 문법 검사 통과(Apache httpd -t/apache2ctl -t, nginx -t, Tomcat configtest - 예전 WEB-04 의
#    "Options -Indexes FollowSymLinks" +/- 혼용, WEB-16/22 의 nginx main 컨텍스트 삽입은 다음 재시작 때 서비스를 죽였다)
# ② 성공(APPLIED)·실패 원복(FAILED_*) 항목이 케이스마다 기대한 집합과 정확히 같음 - 예전에는 APPLIED 0건만 아니면
#    통과라, WEB-18(Debian)·WEB-04/12/19(Options All)·Tomcat /etc 배치 조치가 원복으로 끝나도 몰랐다(F-R4/F-R5).
#    FAILED_NOT_ROLLED_BACK 은 항상 실패.
# ③ --rollback 후 설정 트리 전체(경로·종류·권한·소유자·내용·심볼릭 링크 대상)가 조치 전과 같음 - Debian 의
#    mods-enabled/sites-enabled 링크가 sed -i 로 일반 파일이 되던 문제 포함
# ④ 백업 공간이 없어 백업이 실패하면 설정을 바꾸지 않고 중단(종료코드 3, changes.log ABORTED)
# confirm 모드는 confirm 등급에도 y 로 답한다(WEB-21 은 SSL 미구성이라 "수동 조치 필요" ERROR → 원복이 정상 기대값).
# 형식: 이미지 접미사|fix_safety 인자|기대 APPLIED_CODES|기대 FAILED_CODES
FIX_CASES='apache|apache apply|WEB-04,WEB-14,WEB-16,WEB-22,WEB-26|
apache|apache confirm WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-21,WEB-22,WEB-26|WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-22,WEB-26|WEB-21
nginx|nginx apply|WEB-04,WEB-14,WEB-16,WEB-22,WEB-26|
nginx|nginx confirm WEB-04,WEB-07,WEB-12,WEB-14,WEB-16,WEB-21,WEB-22,WEB-26|WEB-04,WEB-07,WEB-12,WEB-14,WEB-16,WEB-22,WEB-26|WEB-21
apache-debian|apache-debian apply|WEB-04,WEB-14,WEB-16,WEB-18,WEB-22|
apache-debian|apache-debian confirm WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-18,WEB-21,WEB-22|WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-18,WEB-22|WEB-21
apache-debian|apache-debian-opts confirm WEB-04,WEB-12,WEB-19|WEB-04,WEB-12,WEB-19|
tomcat|tomcat confirm WEB-01,WEB-03,WEB-04,WEB-08,WEB-13,WEB-14,WEB-16,WEB-22,WEB-26|WEB-01,WEB-03,WEB-04,WEB-08,WEB-14,WEB-16,WEB-22,WEB-26|
apache-rhel|apache-rhel apply|WEB-04,WEB-14,WEB-16,WEB-18,WEB-19,WEB-22|
apache-rhel|apache-rhel confirm WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-18,WEB-19,WEB-21,WEB-22|WEB-04,WEB-08,WEB-12,WEB-14,WEB-16,WEB-18,WEB-19,WEB-22|WEB-21
tomcat-rhel|tomcat-rhel confirm WEB-01,WEB-03,WEB-04,WEB-08,WEB-13,WEB-14,WEB-16,WEB-22,WEB-26|WEB-01,WEB-03,WEB-04,WEB-08,WEB-14,WEB-16,WEB-22|
tomcat|tomcat-etc confirm WEB-01,WEB-03,WEB-04,WEB-08,WEB-13,WEB-14,WEB-16,WEB-22,WEB-26|WEB-01,WEB-03,WEB-04,WEB-08,WEB-14,WEB-16,WEB-22|'
n=0
while IFS='|' read -r img args exp_app exp_fail; do
    [ -n "$img" ] || continue
    in_engines "$img" || continue
    n=$((n + 1))
    cname="kisa-web-fix-$n"
    docker rm "$cname" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    out=$(docker run --name "$cname" "kisa-web-${img}-test" sh 03_web/tests/fixtures/fix_safety.sh $args < /dev/null)
    docker rm "$cname" >/dev/null 2>&1
    kv() { printf '%s\n' "$out" | sed -n "s/^$1=//p"; }
    why=""
    [ "$(kv FIX_RC)" = 0 ] || why="$why FIX_RC"
    [ "$(kv BASE_SYNTAX_RC)" = 0 ] || why="$why 조치전문법"
    [ "$(kv SYNTAX_RC)" = 0 ] || why="$why 조치후문법"
    [ "$(kv APPLIED_CODES)" = "$exp_app" ] || why="$why APPLIED(기대=$exp_app)"
    [ "$(kv FAILED_CODES)" = "$exp_fail" ] || why="$why FAILED(기대=$exp_fail)"
    [ "$(kv NOT_ROLLED_BACK)" = 0 ] || why="$why 원복실패"
    [ "$(kv ROLLBACK)" = same ] || why="$why 원복후상태다름"
    case "$args" in tomcat-rhel*) [ "$(kv RUNUSER_READ)" = ok ] || why="$why 조치후tomcat계정읽기불가" ;; esac
    if [ -z "$why" ]; then
        echo "PASS: fix/$args ($(printf '%s' "$out" | grep -E '^(APPLIED|FAILED)_CODES=' | tr '\n' ' '))"
    else
        echo "FAIL: fix/$args -$why"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
    fi
done <<EOF_FIX
$FIX_CASES
EOF_FIX
if in_engines apache; then
    docker rm kisa-web-fix-backupfail >/dev/null 2>&1 || true
    out=$(docker run --name kisa-web-fix-backupfail --tmpfs /fixout:size=16k -e FIX_OUT=/fixout kisa-web-apache-test sh 03_web/tests/fixtures/fix_safety.sh apache backupfail < /dev/null)
    docker rm kisa-web-fix-backupfail >/dev/null 2>&1
    if printf '%s\n' "$out" | grep -qx 'FIX_RC=3' && printf '%s\n' "$out" | grep -qx 'CONF=unchanged' && printf '%s\n' "$out" | grep -qx 'ABORTED=1'; then
        echo "PASS: apache/fix-backupfail ($(printf '%s' "$out" | tr '\n' ' '))"
    else
        echo "FAIL: apache/fix-backupfail - $(printf '%s' "$out" | tr '\n' ' ')"; fail=1
    fi
fi

# ---- 진단(run.sh) 운영 안전 실기 검사 (lib/tests/run_safety.sh, 01_unix 와 같은 기준) ---------
# S1 전후 상태 동일 / S2 제한 시간 / S5 비밀값(tomcat-users.xml 비밀번호·keystorePass, Apache ProxyPass URL 비밀번호,
# nginx proxy_pass 토큰 - setup.sh vuln 이 심음) 원문이 출력물 어디에도 없음 / S6 일반 사용자 거짓 양호
for engine in $WEB_ENGINES; do
    run_e=$(run_engine "$engine")
    rs_dir="rs_web_${engine}_$$"
    docker rm -f "kisa-rs-web-$engine" >/dev/null 2>&1 || true
    docker create --name "kisa-rs-web-$engine" "kisa-web-${engine}-test" sh -c "
        sh 03_web/tests/fixtures/setup.sh $engine vuln >/dev/null 2>&1
        RUN_CMD='sh 03_web/run.sh -e $run_e' SECRETS='Leak>Check|Pw9Strong|KsLeak9Pass|Px9#Leak!Pw|Rh9Leak-Pw|Nx7-Leak!Tok' sh lib/tests/run_safety.sh
    " >/dev/null
    docker start -a "kisa-rs-web-$engine" >/dev/null
    docker cp "kisa-rs-web-$engine:/rs" "$rs_dir" >/dev/null 2>&1
    docker rm "kisa-rs-web-$engine" >/dev/null
    # Rocky 9 는 하네스의 일반 사용자 전환(su, pam_lastlog)이 /var/log/lastlog 를 갱신한다 - 진단과 무관(01_unix rhel 과 같은 처리)
    allow=""
    case "$engine" in *-rhel) allow='^[<>] /var/log/lastlog\|' ;; esac
    python3 lib/tests/run_safety_check.py "$rs_dir" "web/$engine" ${allow:+--allow-fs "$allow"} || fail=1
    rm -rf "$rs_dir"
done

# ---- 항목별 양방향 케이스(fixtures/cases/cases.json, 1.4.0) - 위에서 빌드한 이미지를 그대로 쓴다 ---------------
# 케이스마다 새 컨테이너: 상태 변경 확인 → 진단 기대값 → (VULN + 조치 스크립트) 조치·재진단·문법 검사·원복 동일성
sh 03_web/tests/run_cases.sh || fail=1

exit $fail

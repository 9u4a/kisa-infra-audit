#!/bin/sh
# 03_web/tests/run_tests.sh — Docker(공식 httpd:2.4/nginx:latest/tomcat:10) 기반 회귀 테스트.
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
set -eu
export MSYS_NO_PATHCONV=1   # Windows git-bash에서 docker 인자 경로 자동변환 방지(실 Linux에선 무해)

cd "$(dirname "$0")/../.."   # 저장소 루트로 이동

fail=0
for engine in apache nginx tomcat; do
    image="kisa-web-${engine}-test"
    echo "[1/2] $engine 이미지 빌드..."
    docker build -q -f "03_web/tests/Dockerfile.$engine" -t "$image" . >/dev/null

    for mode in vuln hardened; do
        echo "[*] $engine/$mode 픽스처 실행..."
        cid=$(docker create "$image" sh -c "
            sh 03_web/tests/fixtures/setup.sh $engine $mode >/dev/null 2>&1
            sh 03_web/run.sh -e $engine -o /tmp/out >/dev/null 2>&1
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

        if python3 - "$result_file" "03_web/tests/fixtures/expected_${engine}_${mode}.json" "$engine/$mode" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
result_path, expected_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
actual = {it["code"]: it["status"] for it in json.load(open(result_path, encoding="utf-8"))["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
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

exit $fail

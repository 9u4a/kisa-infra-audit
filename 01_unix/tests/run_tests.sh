#!/bin/sh
# 01_unix/tests/run_tests.sh — Docker(Debian 12) 기반 회귀 테스트.
# 저장소 루트에서 실행한다(빌드 컨텍스트가 루트여야 하므로): sh 01_unix/tests/run_tests.sh
#
# vuln/hardened 두 픽스처(fixtures/setup.sh 가 런타임에 적용)로 run.sh 를 실제로 돌려
# fixtures/expected_{vuln,hardened}.json 과 diff 한다. 이 두 expected.json은 "이상적으로
# 완벽히 강화된 상태"를 미리 예측한 값이 아니라, 실제로 이 이미지에서 run.sh를 돌려서 나온
# 결과를 그대로 고정한 것이다(05_network 픽스처와 같은 방식) - fixtures/setup.sh 가 명시적으로
# 건드리는 ~20개 항목 외의 나머지는 "이 Debian 베이스 이미지의 있는 그대로의 기본값"을
# 반영할 뿐이라는 점에 주의할 것(완전한 전수 강화 검증이 아니다).
set -eu
export MSYS_NO_PATHCONV=1   # Windows git-bash에서 docker -v 인자의 경로 자동변환 방지(실 Linux에선 무해)

cd "$(dirname "$0")/../.."   # 저장소 루트로 이동
IMAGE=kisa-u01-test

echo "[1/3] Docker 이미지 빌드..."
docker build -q -f 01_unix/tests/Dockerfile -t "$IMAGE" . >/dev/null

fail=0
# 저장소 경로에 한글이 포함될 수 있는데, 그 상태에서 Docker Desktop(Windows)의 바인드 마운트가
# 조용히 빈 디렉터리로 마운트되는 문제가 있었다(실기 테스트로 발견 - docker run은 성공하는데
# 호스트에 파일이 전혀 나타나지 않음). 바인드 마운트 대신 `docker cp`(컨테이너 ID 기준으로
# 동작, 호스트 경로의 인코딩에 영향받지 않음)로 결과 파일만 꺼낸다 - CI(Linux, ASCII 경로)에서도
# 동일하게 잘 동작한다.
for mode in vuln hardened; do
    echo "[*] $mode 픽스처 실행..."
    cid=$(docker create "$IMAGE" sh -c "
        sh 01_unix/tests/fixtures/setup.sh $mode >/dev/null 2>&1
        sh 01_unix/run.sh -e debian -o /tmp/out >/dev/null 2>&1
        cp /tmp/out/*/result.json /result.json
    ")
    docker start -a "$cid" >/dev/null
    result_file="result_$mode.json"
    docker cp "$cid:/result.json" "$result_file" >/dev/null 2>&1
    docker rm "$cid" >/dev/null

    if [ ! -f "$result_file" ]; then
        echo "FAIL: $mode - 컨테이너에서 result.json 을 꺼내지 못함"
        fail=1
        continue
    fi

    if python3 - "$result_file" "01_unix/tests/fixtures/expected_$mode.json" "$mode" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
result_path, expected_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
actual = {it["code"]: it["status"] for it in json.load(open(result_path, encoding="utf-8"))["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
if failures:
    print(f"FAIL: {mode} - {len(failures)}건 불일치")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: {mode}")
PYEOF
    then :; else fail=1; fi
    rm -f "$result_file"
done

exit $fail

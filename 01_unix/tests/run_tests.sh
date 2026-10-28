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
raw = open(result_path, encoding="utf-8").read()
actual = {it["code"]: it["status"] for it in json.loads(raw)["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
# fixtures/setup.sh 가 /etc/passwd 에 넣은 비밀번호 필드 원문이 결과물에 남으면 안 된다(U-04)
if "plainhash123" in raw:
    failures.append("U-04: /etc/passwd 비밀번호 필드 원문이 result.json 에 저장됨")
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

# ---- 조치(fix) 운영 안전 회귀 테스트 (fixtures/fix_safety.sh) -----------------------
# ① fix.sh 가 중간에 죽지 않음(1.1.0~1.2.1 은 OS_FAMILY 미설정으로 첫 항목에서 "parameter not set"
#    으로 죽었다 - CI 에 조치 테스트가 없어 아무도 몰랐던 회귀)
# ② 대체 관리자가 없으면 U-01 은 sshd_config 를 바꾸지 않음(지연 lockout 방지) - U-01 은 confirm 등급이라
#    일괄 적용에서는 DECLINED, 안전장치는 조치 함수를 직접 호출해 확인(U01_GUARD)
# ③ --rollback 후 핵심 설정 파일의 내용·권한·소유자가 조치 전과 같음
out=$(docker run --rm "$IMAGE" sh 01_unix/tests/fixtures/fix_safety.sh)
if printf '%s\n' "$out" | grep -qx 'FIX_RC=0' && printf '%s\n' "$out" | grep -qx 'CRASH=no' \
   && ! printf '%s\n' "$out" | grep -qx 'APPLIED=0' && printf '%s\n' "$out" | grep -qx 'U01=DECLINED' \
   && printf '%s\n' "$out" | grep -qx 'U01_GUARD=ERROR/unchanged' \
   && printf '%s\n' "$out" | grep -qx 'ROLLBACK=same'; then
    echo "PASS: fix-apply ($(printf '%s' "$out" | tr '\n' ' '))"
else
    echo "FAIL: fix-apply - $(printf '%s' "$out" | tr '\n' ' ')"; fail=1
fi

# ---- 진단(run.sh) 운영 안전 실기 검사 (lib/tests/run_safety.sh) ----------------------
# 진단 전후 파일시스템·/etc 내용·프로세스·/tmp 가 같은지(S1), 비대화형으로 제한 시간 안에 끝나는지(S2),
# 비밀값(/etc/passwd 비밀번호 필드·SNMP community)이 출력물 어디에도 없고 권한이 실행자 전용인지(S5),
# 일반 사용자로 돌렸을 때 root 에서 VULN 인 항목이 GOOD/NA 로 바뀌지 않는지(S6).
# snmpd.conf 의 "rocommunity <값>"(소스 생략) 줄은 1.3.1 까지 U-61 에서 진단 전체를 죽였다 - 재발 방지로 넣어 둔다.
rs_dir="rs_unix_$$"
docker rm -f kisa-rs-unix >/dev/null 2>&1 || true
docker create --name kisa-rs-unix "$IMAGE" sh -c "
    sh 01_unix/tests/fixtures/setup.sh vuln >/dev/null 2>&1
    mkdir -p /etc/snmp && echo 'rocommunity KisaComm77Secret' >> /etc/snmp/snmpd.conf
    RUN_CMD='sh 01_unix/run.sh -e debian' SECRETS='plainhash123|KisaComm77Secret' sh lib/tests/run_safety.sh
" >/dev/null
docker start -a kisa-rs-unix >/dev/null
docker cp kisa-rs-unix:/rs "$rs_dir" >/dev/null 2>&1
docker rm kisa-rs-unix >/dev/null
python3 lib/tests/run_safety_check.py "$rs_dir" 01_unix --expect U-61=VULN || fail=1
rm -rf "$rs_dir"

exit $fail

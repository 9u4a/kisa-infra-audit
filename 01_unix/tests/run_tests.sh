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
# ④ F-R8/F-R9: U-32 가 Debian nologin 계정의 없는 홈 때문에 원복되지 않음, U-59~61 이 include 파일·IPv6·-Cn 까지
#    고쳐 재검증 GOOD·원복 동일, U-01 은 Telnet 이 원인이면 변경 없이 SKIPPED(Telnet 을 끄면 sshd 조치 적용)
# ⑤ 일괄 적용(auto)의 결과를 고정한다: APPLIED 항목 집합이 정확히 같고, 실패(FAILED_*·ABORTED)는 0건, 조치로 해소할 수
#    없어 변경 없이 건너뛴 항목(SKIPPED)도 고정. 예전에는 APPLIED≠0 만 봐서 U-13/15/65 의 실패·원복을 놓쳤다.
#    vuln 픽스처를 바꿔 항목이 늘거나 줄면 이 목록도 함께 고친다(fix_safety.sh 출력의 APPLIED_CODES 참고).
# ⑥ 1.3.4: X-07 U-01 은 기존 설정이 sshd -t 에 실패하면 ERROR·sshd 가 없으면 SKIPPED(둘 다 변경 없음). sed -i 금지 -
#    /etc/pam.d/su 가 심볼릭 링크여도 U-06 조치·원복 뒤 링크 유지. X-04 가짜 조치(백업 → 변경 → 미설정 변수)가 죽어도
#    그 항목만 원복·FAILED_ROLLED_BACK(사유 기록) 후 다음 항목(U-18) 진행, fix_abort_item 은 종료코드 3·ABORTED·다음 항목
#    미변경. X-06 다른 호스트·카테고리·7일 지난 result.json 은 exit 2·변경 없음, --force 면 진행.
FIX_EXPECT_APPLIED='U-09,U-11,U-14,U-15,U-16,U-17,U-18,U-20,U-27,U-30,U-32,U-34,U-35,U-36,U-40,U-52,U-53,U-62,'
FIX_EXPECT_SKIPPED='U-13,U-65,'
out=$(docker run --rm "$IMAGE" sh 01_unix/tests/fixtures/fix_safety.sh)
if printf '%s\n' "$out" | grep -qx 'FIX_RC=0' && printf '%s\n' "$out" | grep -qx 'CRASH=no' \
   && printf '%s\n' "$out" | grep -qx "APPLIED_CODES=$FIX_EXPECT_APPLIED" \
   && printf '%s\n' "$out" | grep -qx "SKIPPED_CODES=$FIX_EXPECT_SKIPPED" \
   && printf '%s\n' "$out" | grep -qx 'FAILED_CODES=' && printf '%s\n' "$out" | grep -qx 'CHANGED=yes' \
   && printf '%s\n' "$out" | grep -qx 'U01=DECLINED' \
   && printf '%s\n' "$out" | grep -qx 'U01_GUARD=ERROR/unchanged' \
   && printf '%s\n' "$out" | grep -qx 'ROLLBACK=same' \
   && printf '%s\n' "$out" | grep -qx 'U32=APPLIED' && printf '%s\n' "$out" | grep -qx 'U32_RB=absent' \
   && printf '%s\n' "$out" | grep -qx 'SNMP_U-61=APPLIED/GOOD/rb-ok' \
   && printf '%s\n' "$out" | grep -qx 'SNMP_U-60=APPLIED/GOOD/rb-ok' \
   && printf '%s\n' "$out" | grep -qx 'SNMP_U-59=APPLIED/GOOD/rb-ok' \
   && printf '%s\n' "$out" | grep -qx 'SNMP_ROLLBACK=same' \
   && printf '%s\n' "$out" | grep -qx 'U01_TELNET=SKIPPED/VULN/unchanged' \
   && printf '%s\n' "$out" | grep -qx 'U01_SSHD=APPLIED/GOOD/rb-ok/same' \
   && printf '%s\n' "$out" | grep -qx 'U01_BADBASE=ERROR/VULN/unchanged' \
   && printf '%s\n' "$out" | grep -qx 'U01_NOSSHD=SKIPPED/VULN/unchanged' \
   && printf '%s\n' "$out" | grep -qx 'PAM_SYMLINK=APPLIED/GOOD/link/target-written/rb-ok/link/same' \
   && printf '%s\n' "$out" | grep -qx 'ISO_RC=0' \
   && printf '%s\n' "$out" | grep -qx 'ISO=U-16:FAILED_ROLLED_BACK,U-18:APPLIED,' \
   && printf '%s\n' "$out" | grep -qx 'ISO_REASON=logged' && printf '%s\n' "$out" | grep -qx 'ISO_TARGET=restored' \
   && printf '%s\n' "$out" | grep -qx 'ABORT_RC=3' && printf '%s\n' "$out" | grep -qx 'ABORT=U-16:ABORTED,' \
   && printf '%s\n' "$out" | grep -qx 'ABORT_TARGET=restored' && printf '%s\n' "$out" | grep -qx 'ABORT_NEXT=untouched' \
   && printf '%s\n' "$out" | grep -qx 'TARGET_HOST=2/unchanged' && printf '%s\n' "$out" | grep -qx 'TARGET_CAT=2' \
   && printf '%s\n' "$out" | grep -qx 'TARGET_OLD=2/unchanged' && printf '%s\n' "$out" | grep -qx 'TARGET_FORCE=0/APPLIED'; then
    echo "PASS: fix-apply ($(printf '%s' "$out" | tr '\n' ' '))"
else
    echo "FAIL: fix-apply - $(printf '%s' "$out" | tr '\n' ' ')"; fail=1
fi

# ---- 항목별 양방향 케이스 (fixtures/cases, 1.4.0) ------------------------------------
# 전역 vuln/hardened 픽스처로 만들 수 없는 상태(서비스 설치+활성/비활성, 서로 배타적인 설정)를 항목마다 새 systemd 컨테이너
# (Dockerfile.cases)에서 만들어 판정을 확인하고, VULN 케이스는 조치 → 재검증 → 원복 → 상태 동일까지 본다(run_cases.sh).
# lib/tests/coverage.py 가 세는 01_unix 양방향 검증의 절반 이상이 여기서 나온다 - 케이스를 빼면 coverage --strict 가 실패.
sh 01_unix/tests/run_cases.sh || fail=1

# ---- 진단(run.sh) 운영 안전 실기 검사 (lib/tests/run_safety.sh) ----------------------
# 진단 전후 파일시스템·/etc 내용·프로세스·/tmp 가 같은지(S1), 비대화형으로 제한 시간 안에 끝나는지(S2),
# 비밀값(/etc/passwd 비밀번호 필드·SNMP community)이 출력물 어디에도 없고 권한이 실행자 전용인지(S5),
# 일반 사용자로 돌렸을 때 root 에서 VULN 인 항목이 GOOD/NA 로 바뀌지 않는지(S6).
# snmpd.conf 의 "rocommunity <값>"(소스 생략) 줄은 1.3.1 까지 U-61 에서 진단 전체를 죽였다 - 재발 방지로 넣어 둔다.
# 1.3.3(F-R 후속): vuln·hardened 두 픽스처 모두, 비 root 결과는 GOOD/NA 0건·항목 집합 동일, 비밀값에 U-13 의 MD5 해시와
# SNMPv3 비밀번호(특수문자 포함 - JSON/HTML 이스케이프를 풀어서도 검색), 외부 명령이 멈추는 경우(HANG_CMDS 가짜를 PATH
# 앞에 둠)에도 HANG_LIMIT 안에 끝나는지(vuln 만 - 시간 절약).
UNIX_SECRETS='plainhash123|KisaComm77Secret|\$1\$kisasalt\$Qp0wYQK0rM1y9vUe6m3Vx/|KisaAuthPass#2026'
UNIX_HANG='systemctl postconf sendmail exim exim4 rpcinfo firewall-cmd hostnamectl nft iptables ypwhich named exportfs showmount'
for mode in vuln hardened; do
    rs_dir="rs_unix_${mode}_$$"
    hang=""; [ "$mode" = "vuln" ] && hang="HANG_CMDS='$UNIX_HANG' HANG_LIMIT=180"
    expect=""; [ "$mode" = "vuln" ] && expect="--expect U-61=VULN"
    docker rm -f "kisa-rs-unix-$mode" >/dev/null 2>&1 || true
    docker create --name "kisa-rs-unix-$mode" "$IMAGE" sh -c "
        sh 01_unix/tests/fixtures/setup.sh $mode >/dev/null 2>&1
        mkdir -p /etc/snmp && echo 'rocommunity KisaComm77Secret' >> /etc/snmp/snmpd.conf
        RUN_CMD='sh 01_unix/run.sh -e debian' SECRETS='$UNIX_SECRETS' $hang sh lib/tests/run_safety.sh
    " >/dev/null
    docker start -a "kisa-rs-unix-$mode" >/dev/null
    docker cp "kisa-rs-unix-$mode:/rs" "$rs_dir" >/dev/null 2>&1
    docker rm "kisa-rs-unix-$mode" >/dev/null
    # shellcheck disable=SC2086
    python3 lib/tests/run_safety_check.py "$rs_dir" "01_unix/$mode" $expect || fail=1
    rm -rf "$rs_dir"
done

exit $fail

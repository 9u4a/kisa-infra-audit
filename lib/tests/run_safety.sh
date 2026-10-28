#!/bin/sh
# lib/tests/run_safety.sh — 진단(run.sh)의 운영 안전 실기 검사(조치의 fix_safety 에 대응).
# Docker 테스트 컨테이너 안에서 root 로 실행한다(저장소 루트가 작업 디렉터리). 대상 시스템을 바꾸는 것은
# 이 스크립트가 아니라 호출 측의 픽스처뿐이다 - 여기서는 진단만 돌리고 관찰한다.
#   RUN_CMD='sh 01_unix/run.sh -e debian' SECRETS='비밀1|비밀2' sh lib/tests/run_safety.sh
# 확인 내용(결과는 /rs 에 남기고 호출 측 lib/tests/run_safety_check.py 가 판정):
#   S1 진단 전후 파일시스템(경로·종류·권한·소유자·크기·mtime)과 /etc 내용 해시, 실행 중 프로세스가 같음,
#      /tmp·/var/tmp 에 남긴 파일 없음
#   S2 비대화형(stdin 닫힘)으로 제한 시간 안에 끝남
#   S5 SECRETS 의 값이 출력물(result.json/csv/summary/report.html/run.log/raw) 어디에도 없음,
#      출력 폴더·파일에 그룹/기타 권한 없음
#   S6 일반 사용자로 실행한 결과를 root 결과와 비교(호출 측) - root 에서 VULN 인 항목이 GOOD/NA 로 바뀌면 거짓 양호
set -u
RS=/rs
rm -rf "$RS" /tmp/rs_root /tmp/rs_nr
mkdir -p "$RS"
LIMIT=${RUN_LIMIT:-900}

snap() {
    find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -path /var/tmp \
        -o -path "$RS" \) -prune -o -printf '%p|%y|%m|%U|%G|%s|%T@\n' 2>/dev/null | sort
}
etc_sum() { find /etc -xdev -type f -exec md5sum {} + 2>/dev/null | sort -k2; }
procs() { for p in /proc/[0-9]*; do cat "$p/comm" 2>/dev/null; done | sort -u; }
tmpls() { ls -A /tmp /var/tmp 2>/dev/null | grep -v '^rs_' | sort; }

snap > "$RS/fs0"; etc_sum > "$RS/etc0"; procs > "$RS/proc0"; tmpls > "$RS/tmp0"

start=$(date +%s)
# shellcheck disable=SC2086
timeout "$LIMIT" $RUN_CMD -o /tmp/rs_root < /dev/null > "$RS/root.out" 2>&1
echo "ROOT_RC=$?" > "$RS/kv"
echo "ROOT_SECONDS=$(( $(date +%s) - start ))" >> "$RS/kv"

snap > "$RS/fs1"; etc_sum > "$RS/etc1"; procs > "$RS/proc1"; tmpls > "$RS/tmp1"
diff "$RS/fs0" "$RS/fs1" > "$RS/fs.diff"
diff "$RS/etc0" "$RS/etc1" > "$RS/etc.diff"
diff "$RS/proc0" "$RS/proc1" | grep '^>' > "$RS/proc.diff"
diff "$RS/tmp0" "$RS/tmp1" | grep '^>' > "$RS/tmp.diff"

# 출력물 권한: 실행자만 접근(그룹/기타 비트 없음)
find /tmp/rs_root -perm /077 > "$RS/perm.bad" 2>/dev/null

# 비밀값 잔존(모든 출력 파일)
: > "$RS/secret.hit"
printf '%s\n' "${SECRETS:-}" | tr '|' '\n' | while IFS= read -r s; do
    [ -n "$s" ] || continue
    grep -rlF -- "$s" /tmp/rs_root 2>/dev/null | sed "s|^|$s :: |" >> "$RS/secret.hit"
done

f=$(find /tmp/rs_root -name result.json | head -n 1)
[ -n "$f" ] && cp "$f" "$RS/root.json"

# 일반 사용자 실행(거짓 양호 비교용) - 저장소를 읽을 수 있어야 한다
id kisa_nr >/dev/null 2>&1 || useradd -M -s /bin/sh kisa_nr 2>/dev/null || adduser -D -H kisa_nr 2>/dev/null
chmod -R a+rX "$(pwd)" 2>/dev/null
start=$(date +%s)
su kisa_nr -s /bin/sh -c "cd '$(pwd)' && timeout $LIMIT $RUN_CMD -o /tmp/rs_nr" < /dev/null > "$RS/nr.out" 2>&1
echo "NR_RC=$?" >> "$RS/kv"
echo "NR_SECONDS=$(( $(date +%s) - start ))" >> "$RS/kv"
f=$(find /tmp/rs_nr -name result.json 2>/dev/null | head -n 1)
[ -n "$f" ] && cp "$f" "$RS/nr.json"
exit 0

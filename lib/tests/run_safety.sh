#!/bin/sh
# lib/tests/run_safety.sh — 진단(run.sh)의 운영 안전 실기 검사(조치의 fix_safety 에 대응).
# Docker 테스트 컨테이너 안에서 root 로 실행한다(저장소 루트가 작업 디렉터리). 대상 시스템을 바꾸는 것은
# 이 스크립트가 아니라 호출 측의 픽스처뿐이다 - 여기서는 진단만 돌리고 관찰한다.
#   RUN_CMD='sh 01_unix/run.sh -e debian' SECRETS='비밀1|비밀2' [HANG_CMDS='systemctl rpcinfo ...'] sh lib/tests/run_safety.sh
# 확인 내용(결과는 /rs 에 남기고 호출 측 lib/tests/run_safety_check.py 가 판정):
#   S1 진단 전후 상태가 같음 - root 실행과 일반 사용자 실행 각각에 대해
#      · 파일시스템(경로·종류·권한·소유자·크기·mtime), /etc 내용 해시
#      · /tmp·/var/tmp·/dev/shm 전체(새 파일·기존 파일 변경·삭제, 진단 출력 폴더만 제외)
#      · 프로세스(PID+명령행, 양방향 - 새로 남은 것·사라진 것). 이 스크립트 자신의 스냅샷 명령만 제외하고,
#        검사용 상주 프로세스(sleep)를 하나 띄워 두어 진단이 기존 프로세스를 죽이지 않는지도 본다
#      · sysctl -a(커널 카운터류 제외), /proc/mounts, iptables-save(있을 때)
#   S2 비대화형(stdin 닫힘)으로 제한 시간 안에 끝남. HANG_CMDS 가 있으면 그 명령들을 "영원히 멈추는" 가짜로 PATH 앞에
#      두고 한 번 더 실행해 HANG_LIMIT(기본 180초) 안에 끝나는지 본다(외부 명령 시간 제한 run_to 누락 검출)
#   S5 SECRETS 의 값이 출력물(root·일반 사용자 결과 폴더 전체, root.out, nr.out) 어디에도 없음 - JSON/HTML 이스케이프를
#      풀어서도 검색(판정은 python 쪽), 출력 폴더·파일에 그룹/기타 권한 없음(root·일반 사용자 모두)
#   S6 일반 사용자로 실행한 결과를 root 결과와 비교(호출 측)
# 인터페이스(RUN_CMD·SECRETS·RUN_LIMIT, /rs 의 kv·root.json·nr.json·fs.diff·etc.diff·proc.diff·tmp.diff·perm.bad·
# secret.hit)는 1.3.2 와 호환된다. 추가 파일: sys.diff, nr_*.diff, nr_perm.bad, secrets, out/(출력물 사본), hang.*
set -u
RS=/rs
rm -rf "$RS" /tmp/rs_root /tmp/rs_nr /tmp/rs_hang /tmp/rs_hangout
mkdir -p "$RS"
LIMIT=${RUN_LIMIT:-900}
SELF=$$

snap_fs() {
    find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -path /var/tmp \
        -o -path "$RS" \) -prune -o -printf '%p|%y|%m|%U|%G|%s|%T@\n' 2>/dev/null | sort
}
snap_etc() { find /etc -xdev -type f -exec md5sum {} + 2>/dev/null | sort -k2; }
# 임시 영역 전체(진단 출력 폴더만 제외) - 새 파일뿐 아니라 기존 파일의 변경·삭제도 잡는다
snap_tmp() {
    for d in /tmp /var/tmp /dev/shm; do
        [ -d "$d" ] || continue
        # 디렉터리 mtime 은 뺀다 - 하네스 출력 폴더(rs_*)를 만들면 /tmp 자체 mtime 이 바뀌고, 하위 항목의 추가·삭제는
        # 항목 목록 비교로 이미 잡힌다(03_web 4개 엔진에서 "/tmp mtime 변경" 거짓 FAIL)
        find "$d" \( -path /tmp/rs_root -o -path /tmp/rs_nr -o -path /tmp/rs_hang -o -path /tmp/rs_hangout \) -prune \
            -o -type d -printf '%p|%y|%m|%U|%G\n' -o -printf '%p|%y|%m|%U|%G|%s|%T@\n' 2>/dev/null
        find "$d" \( -path /tmp/rs_root -o -path /tmp/rs_nr -o -path /tmp/rs_hang -o -path /tmp/rs_hangout \) -prune \
            -o -type f -exec md5sum {} + 2>/dev/null | awk '{ print $2 "|md5|" $1 }'
    done | sort
}
# 프로세스: "PID|명령행". 이 셸($SELF)의 자손(스냅샷 파이프라인 자체)만 뺀다.
snap_procs() {
    for p in /proc/[0-9]*; do
        pid=${p#/proc/}
        st=$(cat "$p/stat" 2>/dev/null) || continue
        ppid=$(printf '%s' "$st" | sed 's/.*) //' | awk '{ print $2 }')
        # 명령행 안의 줄바꿈·탭(awk 프로그램 인자 등)도 공백으로 - 한 프로세스가 여러 줄로 쪼개지지 않게
        cmd=$(tr '\0\n\t' '   ' < "$p/cmdline" 2>/dev/null)
        [ -n "$cmd" ] || cmd="[$(cat "$p/comm" 2>/dev/null)]"
        printf '%s\t%s\t%s\n' "$pid" "$ppid" "$cmd"
    done | awk -F'\t' -v self="$SELF" '
        { pp[$1] = $2; c[$1] = $3; o[++n] = $1 }
        END { for (i = 1; i <= n; i++) { p = o[i]; d = 0; q = p
                  for (k = 0; k < 64 && q != "" && q != "0"; k++) { if (q == self) { d = 1; break }; q = pp[q] }
                  if (!d) print p "|" c[p] } }' | sort
}
# 커널·마운트·방화벽 상태. sysctl 은 시간에 따라 저절로 바뀌는 카운터·난수·다른 컨테이너 영향 값을 뺀다.
snap_sys() {
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -a 2>/dev/null | grep -vE '^(kernel\.random\.|kernel\.ns_last_pid|kernel\.pty\.nr|fs\.(dentry-state|inode-nr|inode-state|file-nr|aio-nr|quota\.)|net\.netfilter\.nf_conntrack_count|kernel\.sched_domain|vm\.stat_refresh|fs\.binfmt_misc|kernel\.tainted|net\.ipv4\.tcp_mem|net\.ipv4\.udp_mem|kernel\.perf_event_max)' \
            | sed 's/^/sysctl:/'
    fi
    sed 's/^/mount:/' /proc/mounts 2>/dev/null
    command -v iptables-save >/dev/null 2>&1 && iptables-save 2>/dev/null | grep -v '^#' | sed 's/^/ipt:/'
    return 0
}
snap_all() {   # <접두어>
    snap_fs > "$RS/$1fs"; snap_etc > "$RS/$1etc"; snap_tmp > "$RS/$1tmp"; snap_procs > "$RS/$1proc"; snap_sys > "$RS/$1sys"
}
diff_all() {   # <전 접두어> <후 접두어> <결과 접두어>
    diff "$RS/$1fs" "$RS/$2fs" > "$RS/$3fs.diff"
    diff "$RS/$1etc" "$RS/$2etc" > "$RS/$3etc.diff"
    diff "$RS/$1tmp" "$RS/$2tmp" | grep '^[<>]' > "$RS/$3tmp.diff"
    diff "$RS/$1proc" "$RS/$2proc" | grep '^[<>]' > "$RS/$3proc.diff"
    diff "$RS/$1sys" "$RS/$2sys" | grep '^[<>]' > "$RS/$3sys.diff"
}

# 진단이 기존 프로세스를 죽이지 않는지 보기 위한 상주 프로세스(서브셸에서 띄우고 서브셸은 끝나 - 이 셸의 자손이 아니게 됨)
( sleep 99999 < /dev/null > /dev/null 2>&1 & )
sleep 1

printf '%s\n' "${SECRETS:-}" | tr '|' '\n' | grep -v '^$' > "$RS/secrets"

# ---- root 실행 ----
snap_all 0_
start=$(date +%s)
# shellcheck disable=SC2086
timeout "$LIMIT" $RUN_CMD -o /tmp/rs_root < /dev/null > "$RS/root.out" 2>&1
echo "ROOT_RC=$?" > "$RS/kv"
echo "ROOT_SECONDS=$(( $(date +%s) - start ))" >> "$RS/kv"
snap_all 1_
diff_all 0_ 1_ ""

# 출력물 권한: 실행자만 접근(그룹/기타 비트 없음)
find /tmp/rs_root -perm /077 > "$RS/perm.bad" 2>/dev/null
f=$(find /tmp/rs_root -name result.json | head -n 1)
[ -n "$f" ] && cp "$f" "$RS/root.json"

# ---- 일반 사용자 실행(거짓 양호 비교용) - 저장소를 읽을 수 있어야 한다 ----
id kisa_nr >/dev/null 2>&1 || useradd -M -s /bin/sh kisa_nr 2>/dev/null || adduser -D -H kisa_nr 2>/dev/null
chmod -R a+rX "$(pwd)" 2>/dev/null
snap_all 2_
start=$(date +%s)
su kisa_nr -s /bin/sh -c "cd '$(pwd)' && timeout $LIMIT $RUN_CMD -o /tmp/rs_nr" < /dev/null > "$RS/nr.out" 2>&1
echo "NR_RC=$?" >> "$RS/kv"
echo "NR_SECONDS=$(( $(date +%s) - start ))" >> "$RS/kv"
snap_all 3_
diff_all 2_ 3_ nr_
find /tmp/rs_nr -perm /077 > "$RS/nr_perm.bad" 2>/dev/null
f=$(find /tmp/rs_nr -name result.json 2>/dev/null | head -n 1)
[ -n "$f" ] && cp "$f" "$RS/nr.json"

# ---- S2: 외부 명령이 멈추는 경우(선택) ----
if [ -n "${HANG_CMDS:-}" ]; then
    mkdir -p /tmp/rs_hang
    for c in $HANG_CMDS; do printf '#!/bin/sh\nexec sleep 9999\n' > "/tmp/rs_hang/$c"; chmod 755 "/tmp/rs_hang/$c"; done
    start=$(date +%s)
    # shellcheck disable=SC2086
    PATH="/tmp/rs_hang:$PATH" timeout -k 5 "${HANG_LIMIT:-180}" $RUN_CMD -o /tmp/rs_hangout < /dev/null > "$RS/hang.out" 2>&1
    echo "HANG_RC=$?" >> "$RS/kv"
    echo "HANG_SECONDS=$(( $(date +%s) - start ))" >> "$RS/kv"
    f=$(find /tmp/rs_hangout -name result.json 2>/dev/null | head -n 1)
    [ -n "$f" ] && cp "$f" "$RS/hang.json"
    sleep 1
    # 진단이 끝난 뒤에도 남은 가짜 명령(시간 제한 없이 백그라운드로 남은 호출)
    echo "HANG_LEFT=$(pgrep -f '^sleep 9999$' 2>/dev/null | wc -l)" >> "$RS/kv"
    pkill -f '^sleep 9999$' 2>/dev/null
fi

# ---- 비밀값 검색용 출력물 사본(판정은 run_safety_check.py 가 이스케이프를 풀어 가며 한다) ----
mkdir -p "$RS/out"
cp "$RS/root.out" "$RS/nr.out" "$RS/out/" 2>/dev/null
[ -d /tmp/rs_root ] && cp -r /tmp/rs_root "$RS/out/root" 2>/dev/null
[ -d /tmp/rs_nr ] && cp -r /tmp/rs_nr "$RS/out/nr" 2>/dev/null
# 1.3.2 호환: 원문 그대로의 검색 결과
: > "$RS/secret.hit"
while IFS= read -r s; do
    [ -n "$s" ] || continue
    grep -rlF -- "$s" "$RS/out" 2>/dev/null | sed "s|^|$s :: |" >> "$RS/secret.hit"
done < "$RS/secrets"
chmod -R a+rX "$RS" 2>/dev/null
pkill -f '^sleep 99999$' 2>/dev/null
exit 0

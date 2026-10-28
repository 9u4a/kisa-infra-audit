# U-27 (상) $HOME/.rhosts, hosts.equiv 사용 금지
# 판단 기준(가이드 원문): 양호 = r-command(rlogin/rsh/rexec) 미사용, 또는 사용 시
#   1) 소유자가 root/해당 계정  2) 권한 600 이하  3) "+" 설정 없음  을 모두 충족
#                        취약 = r-command 사용하며 위 조건 중 하나라도 미충족
# 전 Unix 계열 공통 로직. rsh/rlogin 관련 데몬 유무로 서비스 사용 여부를 우선 판단.

run_check() {
    rcmd_running=0
    for bin_pattern in in.rshd in.rlogind rshd rlogind; do
        command -v "$bin_pattern" >/dev/null 2>&1 && rcmd_running=1
    done
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet rsh.socket 2>/dev/null && rcmd_running=1
        systemctl is-active --quiet rlogin.socket 2>/dev/null && rcmd_running=1
    fi
    grep -qE '^[[:space:]]*(shell|login|exec)[[:space:]]' /etc/inetd.conf 2>/dev/null && rcmd_running=1
    grep -rlqE 'disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/rlogin /etc/xinetd.d/rsh /etc/xinetd.d/rexec 2>/dev/null && rcmd_running=1

    if [ "$rcmd_running" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="rlogin/rsh/rexec(r-command) 서비스를 사용하지 않음"
        CHECK_EVIDENCE=""
        return
    fi

    violations=""
    evidence=""
    skipped=""
    # 진단 검수 U-R14: 예전에는 소유자를 읽고도 비교하지 않았고, "+" 는 줄 맨 앞만 봐서 "host +"(그 호스트의 모든
    # 사용자 신뢰) 형태를 놓쳤으며, 계정 홈을 모두 stat 해 autofs/NFS 홈에서 마운트 연쇄·멈춤 위험이 있었다.
    # 이제 소유자(hosts.equiv=root, .rhosts=root 또는 해당 계정)를 비교하고, 주석이 아닌 줄의 어느 필드든 "+" 이거나
    # 첫 필드가 "+" 로 시작하면 위반으로 본다. 원격·자동마운트 홈은 건드리지 않고 수동 확인 대상으로 남긴다.
    check_file_plus() {
        _f=$1; _allowed=$2
        [ -f "$_f" ] || return
        owner=$(run_to 10 stat -L -c '%U' "$_f" 2>/dev/null)
        perm=$(run_to 10 stat -L -c '%a' "$_f" 2>/dev/null)
        plus=$(awk '$0 !~ /^[[:space:]]*#/ { hit = ($1 ~ /^\+/); for (i = 2; i <= NF; i++) if ($i == "+") hit = 1; if (hit) c++ } END { print c + 0 }' "$_f" 2>/dev/null)
        evidence="$evidence
$(ls -l "$_f" 2>/dev/null) / 소유자 허용: $_allowed / '+' 설정 라인 수: $plus"
        if [ -z "$owner" ] || [ -z "$perm" ]; then
            violations="$violations $_f(소유자/권한 확인 불가)"
        elif ! printf ' %s ' "$_allowed" | grep -q " $owner "; then
            violations="$violations $_f(소유자 $owner)"
        elif perm_exceeds "$perm" 600 || [ "$plus" -gt 0 ] 2>/dev/null; then
            violations="$violations $_f"
        fi
    }

    check_file_plus /etc/hosts.equiv root
    passwd_file="/etc/passwd"
    if [ -r "$passwd_file" ]; then
        # 파이프(| while) 서브셸에서는 violations 가 전달되지 않으므로 here-doc 사용
        while IFS=: read -r u _ _ _ _ h _; do
            [ -n "$h" ] || continue
            if is_remote_or_auto_fs "$h"; then
                skipped="$skipped $h"
                continue
            fi
            check_file_plus "$h/.rhosts" "root $u"
        done <<EOF
$(awk -F: '!seen[$1]++ { print }' "$passwd_file")
EOF
    fi

    if [ -z "$violations" ] && [ -n "$skipped" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="원격·자동마운트(NFS/autofs 등) 위의 홈 디렉터리는 마운트를 유발하지 않도록 확인하지 않음 - 해당 홈의 .rhosts 수동 확인 필요:$skipped"
        CHECK_EVIDENCE="$evidence"
    elif [ -z "$evidence" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="r-command 서비스는 활성화되어 있으나 hosts.equiv/.rhosts 파일이 존재하지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="r-command 사용 중이나 hosts.equiv/.rhosts 파일의 소유자·권한·'+' 설정이 모두 안전함"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="r-command 사용 중이며 기준을 위반하는 파일이 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

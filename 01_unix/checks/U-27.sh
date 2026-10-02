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
    check_file_plus() {
        _f=$1
        [ -f "$_f" ] || return
        owner=$(stat -L -c '%U' "$_f" 2>/dev/null)
        perm=$(stat -L -c '%a' "$_f" 2>/dev/null)
        plus=$(grep -c '^[[:space:]]*+' "$_f" 2>/dev/null)
        evidence="$evidence
$(ls -l "$_f" 2>/dev/null) / '+' 설정 라인 수: $plus"
        if [ "$perm" -gt 600 ] 2>/dev/null || [ "$plus" -gt 0 ] 2>/dev/null; then
            violations="$violations $_f"
        fi
    }

    check_file_plus /etc/hosts.equiv
    passwd_file="/etc/passwd"
    if [ -r "$passwd_file" ]; then
        homes=$(awk -F: '{print $6}' "$passwd_file" | sort -u)
        for h in $homes; do
            check_file_plus "$h/.rhosts"
        done
    fi

    if [ -z "$evidence" ]; then
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

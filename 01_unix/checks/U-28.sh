# U-28 (상) 접속 IP 및 포트 제한
# 판단 기준(가이드 원문): 양호 = 접속을 허용할 특정 호스트에 대한 IP/포트 제한을 설정한 경우
#                        취약 = 설정하지 않은 경우
# 자동화 범위: LINUX(rhel/debian) 의 firewalld/ufw/iptables/nftables/TCP Wrapper 중
#             하나라도 실제 제한 규칙이 있으면 GOOD 으로 판정.

run_check() {
    evidence=""
    found=0

    # nft/iptables/ufw 규칙은 root 만 읽을 수 있다 - 비root 로 돌면 출력이 비어 "제한 없음 = 취약"으로 오인된다.
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="방화벽 규칙 조회는 root 권한이 필요함(권한 부족 시 규칙이 없는 것처럼 보여 판정 불가)"; CHECK_EVIDENCE=""
        return
    fi

    # firewall-cmd 는 D-Bus 경유라 서비스 장애 시 오래 멈출 수 있어 시간 제한을 둔다(lib/common.sh run_to)
    if command -v firewall-cmd >/dev/null 2>&1 && run_to 15 firewall-cmd --state 2>/dev/null | grep -q running; then
        rules=$(run_to 15 firewall-cmd --list-all 2>/dev/null)
        evidence="$evidence
[firewalld]
$rules"
        sources_line=$(printf '%s\n' "$rules" | grep -E '^[[:space:]]*sources:' | sed 's/^[[:space:]]*sources:[[:space:]]*//')
        richrule_count=$(printf '%s\n' "$rules" | grep -c 'rule family=')
        if [ -n "$sources_line" ] || [ "$richrule_count" -gt 0 ] 2>/dev/null; then
            found=1
        fi
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw_status=$(ufw status 2>/dev/null)
        evidence="$evidence
[ufw]
$ufw_status"
        printf '%s' "$ufw_status" | grep -q "Status: active" && \
        printf '%s' "$ufw_status" | grep -qE '^\S+.*(ALLOW|DENY|LIMIT)' && found=1
    fi

    # 예전에는 규칙셋이 비어 있지만 않으면(정책 accept 체인만 있어도) GOOD 이었다(진단 검수 U-R3).
    # 이제 input 훅 체인이 "policy drop" 이거나 그 안에 drop/reject 규칙이 있어야 "제한"으로 본다.
    if command -v nft >/dev/null 2>&1; then
        nft_rules=$(run_to 15 nft list ruleset 2>/dev/null)
        nft_input=$(printf '%s\n' "$nft_rules" | awk '
            /^[[:space:]]*chain[[:space:]]/ { inhook = 0; next }
            /hook[[:space:]]+input/ { inhook = 1; if ($0 ~ /policy[[:space:]]+drop/) { print "policy drop"; exit } ; next }
            inhook && /(^|[[:space:]])(drop|reject)([[:space:]]|;|$)/ { print "rule: " $0; exit }')
        if [ -n "$nft_input" ]; then
            evidence="$evidence
[nftables input 훅 제한: $(printf '%s' "$nft_input" | sed 's/^[[:space:]]*//')]"
            found=1
        elif [ -n "$nft_rules" ]; then
            evidence="$evidence
[nftables 규칙셋은 있으나 input 훅 체인에 drop 정책/drop·reject 규칙 없음]"
        fi
    fi

    if command -v iptables >/dev/null 2>&1; then
        # legacy iptables 는 ip_tables 모듈이 없으면 조회만으로 커널 모듈을 자동 적재한다(S1, 진단 검수 U-R18).
        # 모듈이 아직 없으면(/proc/net/ip_tables_names 부재) legacy 규칙도 있을 수 없으므로 호출하지 않는다.
        ipt_ver=$(run_to 5 iptables -V 2>/dev/null)
        if printf '%s' "$ipt_ver" | grep -q 'nf_tables' || [ -e /proc/net/ip_tables_names ]; then
            # -w: xtables 잠금을 기다린다(없으면 동시에 규칙을 바꾸는 다른 도구와 경합). 대기는 run_to 로 제한.
            # 예전에는 INPUT 규칙이 1개라도(ACCEPT all 포함) 있으면 GOOD 이었다(진단 검수 U-R3) - 이제 기본 정책이
            # DROP 이거나 DROP/REJECT 규칙이 있어야 "제한"으로 본다.
            ipt=$(run_to 15 iptables -w -S INPUT 2>/dev/null)
            ipt_restrict=$(printf '%s\n' "$ipt" | grep -E '^-P INPUT DROP|^-A INPUT .*-j (DROP|REJECT)' | head -n 3)
            evidence="$evidence
[iptables -S INPUT]
$ipt"
            [ -n "$ipt_restrict" ] && found=1
        else
            evidence="$evidence
[iptables(legacy): ip_tables 모듈 미적재 - 규칙 없음(조회 시 모듈 자동 적재를 피하려고 호출하지 않음)]"
        fi
    fi

    if [ -f /etc/hosts.deny ] && [ -f /etc/hosts.allow ]; then
        deny_all=$(grep -cE '^[[:space:]]*ALL[[:space:]]*:[[:space:]]*ALL' /etc/hosts.deny 2>/dev/null)
        allow_lines=$(grep -vcE '^[[:space:]]*(#|$)' /etc/hosts.allow 2>/dev/null)
        evidence="$evidence
[TCP Wrapper] hosts.deny ALL:ALL=$deny_all, hosts.allow 유효 라인=$allow_lines"
        [ "$deny_all" -gt 0 ] 2>/dev/null && [ "$allow_lines" -gt 0 ] 2>/dev/null && found=1
    fi

    if [ "$found" -eq 1 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="방화벽/TCP Wrapper 등으로 접속 허용 IP·포트가 제한되어 있음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="firewalld/ufw/iptables/nftables/TCP Wrapper 어디에서도 접속 제한 설정을 확인하지 못함"
    fi
    CHECK_EVIDENCE="$evidence"
}

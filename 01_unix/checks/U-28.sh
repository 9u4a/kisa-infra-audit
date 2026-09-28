# U-28 (상) 접속 IP 및 포트 제한
# 판단 기준(가이드 원문): 양호 = 접속을 허용할 특정 호스트에 대한 IP/포트 제한을 설정한 경우
#                        취약 = 설정하지 않은 경우
# 자동화 범위: LINUX(rhel/debian) 의 firewalld/ufw/iptables/nftables/TCP Wrapper 중
#             하나라도 실제 제한 규칙이 있으면 GOOD 으로 판정.

run_check() {
    evidence=""
    found=0

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        rules=$(firewall-cmd --list-all 2>/dev/null)
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

    if command -v nft >/dev/null 2>&1; then
        nft_rules=$(nft list ruleset 2>/dev/null)
        if [ -n "$nft_rules" ]; then
            evidence="$evidence
[nftables 규칙 존재]"
            found=1
        fi
    fi

    if command -v iptables >/dev/null 2>&1; then
        ipt=$(iptables -L INPUT -n 2>/dev/null)
        if [ -n "$ipt" ]; then
            rule_lines=$(printf '%s\n' "$ipt" | tail -n +3 | grep -c .)
            evidence="$evidence
[iptables INPUT 규칙 수: $rule_lines]"
            [ "$rule_lines" -gt 0 ] 2>/dev/null && found=1
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

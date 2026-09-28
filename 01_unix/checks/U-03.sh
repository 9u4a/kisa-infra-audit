# U-03 (상) 계정 잠금 임계값 설정
# 판단 기준(가이드 원문): 양호 = 계정 잠금 임계값이 10회 이하로 설정된 경우
#                        취약 = 설정되어 있지 않거나 10회 이하로 설정되지 않은 경우
# 자동화 범위: LINUX(rhel/debian) 의 pam_faillock.so / pam_tally(2).so / faillock.conf 만 판정.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            pam_files="/etc/pam.d/system-auth /etc/pam.d/password-auth /etc/pam.d/common-auth"
            faillock_conf="/etc/security/faillock.conf"
            deny=""
            evidence=""

            for f in $pam_files; do
                [ -f "$f" ] || continue
                line=$(grep -E 'pam_(faillock|tally2?)\.so' "$f" 2>/dev/null | grep -E 'deny=' | head -n1)
                if [ -n "$line" ]; then
                    evidence="$evidence
$f: $line"
                    d=$(printf '%s' "$line" | sed -nE 's/.*deny=([0-9]+).*/\1/p')
                    [ -n "$d" ] && deny="$d"
                fi
            done

            if [ -z "$deny" ] && [ -f "$faillock_conf" ]; then
                line=$(grep -E '^[[:space:]]*deny[[:space:]]*=' "$faillock_conf" 2>/dev/null | tail -n1)
                if [ -n "$line" ]; then
                    evidence="$evidence
$faillock_conf: $line"
                    deny=$(printf '%s' "$line" | sed -nE 's/.*deny[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p')
                fi
            fi

            if [ -z "$deny" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="pam_faillock/pam_tally deny 설정 또는 faillock.conf 설정을 찾을 수 없음 (계정 잠금 임계값 미설정)"
            elif [ "$deny" -ge 1 ] 2>/dev/null && [ "$deny" -le 10 ] 2>/dev/null; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="계정 잠금 임계값 deny=${deny} (10회 이하)로 설정됨"
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="계정 잠금 임계값 deny=${deny} 로 10회를 초과하여 설정됨"
            fi
            CHECK_EVIDENCE=$(printf '%s' "$evidence" | sed '/^$/d')
            [ -z "$CHECK_EVIDENCE" ] && CHECK_EVIDENCE="관련 설정 라인을 찾지 못함"
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (0.2.0에서 SOLARIS/AIX/HP-UX 지원 예정)"
            CHECK_EVIDENCE=""
            ;;
    esac
}

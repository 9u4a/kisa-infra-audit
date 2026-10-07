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
        solaris)
            # /etc/default/login 의 RETRIES - 실패 허용 횟수(문서 기준, 미검증).
            dp="/etc/default/login"
            retries=""
            if [ -f "$dp" ]; then
                retries=$(grep -E '^[[:space:]]*RETRIES=' "$dp" 2>/dev/null | tail -n1 | sed -E 's/.*=//')
            fi
            if [ -z "$retries" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$dp 에 RETRIES 설정이 없어 계정 잠금 임계값이 설정되어 있지 않음"
            elif [ "$retries" -ge 1 ] 2>/dev/null && [ "$retries" -le 10 ] 2>/dev/null; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="계정 잠금 임계값 RETRIES=${retries} (10회 이하)로 설정됨"
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="계정 잠금 임계값 RETRIES=${retries} 로 10회를 초과하여 설정됨"
            fi
            CHECK_EVIDENCE="$dp: RETRIES=${retries:-미설정}"
            ;;
        aix)
            # /etc/security/user default 스탠자의 loginretries - AIX는 기본값이 0(무제한)이라
            # 명시적으로 설정하지 않으면 잠금이 전혀 동작하지 않는다(AIX 보안 가이드에 문서화된
            # 잘 알려진 기본값 - 추측이 아님, 가이드 원문이 명시한 기본값만 신뢰하는 원칙과 동일).
            secuser="/etc/security/user"
            retries=""
            if [ -f "$secuser" ]; then
                retries=$(awk '/^default:/{d=1;next} /^[a-zA-Z0-9_]+:/{d=0} d&&/loginretries[[:space:]]*=/{print;exit}' "$secuser" | sed -E 's/.*=[[:space:]]*//')
            fi
            if [ -z "$retries" ] || [ "$retries" -eq 0 ] 2>/dev/null; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$secuser 의 loginretries 가 미설정 또는 0(기본값, 무제한)이라 계정 잠금이 동작하지 않음"
            elif [ "$retries" -le 10 ] 2>/dev/null; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="계정 잠금 임계값 loginretries=${retries} (10회 이하)로 설정됨"
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="계정 잠금 임계값 loginretries=${retries} 로 10회를 초과하여 설정됨"
            fi
            CHECK_EVIDENCE="$secuser(default): loginretries=${retries:-미설정(기본값 0=무제한)}"
            ;;
        hpux)
            # 표준 모드: /etc/default/security AUTH_MAXTRIES. Trusted Mode: u_maxtries.
            defsec="/etc/default/security"
            tcbdef="/tcb/files/auth/system/default"
            retries=""; src=""
            if [ -f "$defsec" ]; then
                retries=$(grep -E '^[[:space:]]*AUTH_MAXTRIES=' "$defsec" 2>/dev/null | tail -n1 | sed -E 's/.*=//')
                src="$defsec"
            elif [ -f "$tcbdef" ]; then
                retries=$(grep -E ':u_maxtries#' "$tcbdef" 2>/dev/null | sed -E 's/.*u_maxtries#([0-9]+).*/\1/')
                src="$tcbdef(Trusted Mode)"
            fi
            if [ -z "$retries" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="AUTH_MAXTRIES/u_maxtries 설정을 찾지 못해 계정 잠금 임계값이 설정되어 있지 않음"
                CHECK_EVIDENCE="$defsec / $tcbdef 확인 불가"
            elif [ "$retries" -ge 1 ] 2>/dev/null && [ "$retries" -le 10 ] 2>/dev/null; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="계정 잠금 임계값 ${retries}회 (10회 이하)로 설정됨"
                CHECK_EVIDENCE="${src}: ${retries}"
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="계정 잠금 임계값 ${retries}회 로 10회를 초과하여 설정됨"
                CHECK_EVIDENCE="${src}: ${retries}"
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}

# U-02 (상) 비밀번호 관리정책 설정
# 판단 기준(가이드 원문): 양호 = 비밀번호 관리 정책(복잡성·주기)이 설정된 경우
# 자동화 범위: LINUX(rhel/debian) 의 /etc/login.defs(주기) + pwquality.conf(복잡성) 판정.
# Solaris/AIX/HP-UX 는 OS 고유 정책 파일(§카테고리 고유 주의사항 - 문서 기준, 미검증)로 판정.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            logindefs="/etc/login.defs"
            pwquality="/etc/security/pwquality.conf"
            evidence=""
            ok_count=0
            checks_total=0

            if [ -f "$logindefs" ]; then
                max_days=$(grep -E '^[[:space:]]*PASS_MAX_DAYS' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
                min_days=$(grep -E '^[[:space:]]*PASS_MIN_DAYS' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
                evidence="$evidence
$logindefs: PASS_MAX_DAYS=${max_days:-미설정} PASS_MIN_DAYS=${min_days:-미설정}"
                checks_total=$((checks_total + 1))
                if [ -n "$max_days" ] && [ "$max_days" -le 90 ] 2>/dev/null; then
                    ok_count=$((ok_count + 1))
                fi
            fi

            if [ -f "$pwquality" ]; then
                minlen=$(grep -E '^[[:space:]]*minlen' "$pwquality" 2>/dev/null | tail -n1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                evidence="$evidence
$pwquality: minlen=${minlen:-미설정}"
                checks_total=$((checks_total + 1))
                if [ -n "$minlen" ] && [ "$minlen" -ge 8 ] 2>/dev/null; then
                    ok_count=$((ok_count + 1))
                fi
            fi

            if [ "$checks_total" -eq 0 ]; then
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="login.defs / pwquality.conf 파일을 찾을 수 없어 자동 판정 불가"
            elif [ "$ok_count" -eq "$checks_total" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="비밀번호 주기(90일 이하) 및 최소 길이(8자 이상) 정책이 설정됨"
            elif [ "$ok_count" -eq 0 ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="비밀번호 주기·복잡성 정책이 설정되어 있지 않음"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="일부 정책만 설정됨 (주기 또는 복잡성 중 하나 누락) — 수동 확인 필요"
            fi
            CHECK_EVIDENCE=$(printf '%s' "$evidence" | sed '/^$/d')
            ;;
        solaris)
            # /etc/default/passwd: MAXWEEKS(주기, 1주=7일), PASSLENGTH(최소 길이)
            dp="/etc/default/passwd"
            evidence=""; ok_count=0; checks_total=0
            if [ -f "$dp" ]; then
                maxweeks=$(grep -E '^[[:space:]]*MAXWEEKS=' "$dp" 2>/dev/null | tail -n1 | sed -E 's/.*=//')
                passlen=$(grep -E '^[[:space:]]*PASSLENGTH=' "$dp" 2>/dev/null | tail -n1 | sed -E 's/.*=//')
                evidence="$dp: MAXWEEKS=${maxweeks:-미설정} PASSLENGTH=${passlen:-미설정}"
                checks_total=2
                [ -n "$maxweeks" ] && [ "$maxweeks" -le 13 ] 2>/dev/null && ok_count=$((ok_count + 1))
                [ -n "$passlen" ] && [ "$passlen" -ge 8 ] 2>/dev/null && ok_count=$((ok_count + 1))
            fi
            if [ "$checks_total" -eq 0 ]; then
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="$dp 를 찾을 수 없어 자동 판정 불가"
            elif [ "$ok_count" -eq "$checks_total" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="비밀번호 주기(13주 이하) 및 최소 길이(8자 이상) 정책이 설정됨"
            elif [ "$ok_count" -eq 0 ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 주기·최소 길이 정책이 설정되어 있지 않음"
            else
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="일부 정책만 설정됨 — 수동 확인 필요"
            fi
            CHECK_EVIDENCE="$evidence"
            ;;
        aix)
            # /etc/security/user default 스탠자: maxage(주), minlen(최소 길이)
            secuser="/etc/security/user"
            evidence=""; ok_count=0; checks_total=0
            if [ -f "$secuser" ]; then
                maxage=$(awk '/^default:/{d=1;next} /^[a-zA-Z0-9_]+:/{d=0} d&&/maxage[[:space:]]*=/{print;exit}' "$secuser" | sed -E 's/.*=[[:space:]]*//')
                minlen=$(awk '/^default:/{d=1;next} /^[a-zA-Z0-9_]+:/{d=0} d&&/minlen[[:space:]]*=/{print;exit}' "$secuser" | sed -E 's/.*=[[:space:]]*//')
                evidence="$secuser(default stanza): maxage=${maxage:-미설정} minlen=${minlen:-미설정}"
                checks_total=2
                [ -n "$maxage" ] && [ "$maxage" -le 13 ] 2>/dev/null && ok_count=$((ok_count + 1))
                [ -n "$minlen" ] && [ "$minlen" -ge 8 ] 2>/dev/null && ok_count=$((ok_count + 1))
            fi
            if [ "$checks_total" -eq 0 ]; then
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="$secuser 를 찾을 수 없어 자동 판정 불가"
            elif [ "$ok_count" -eq "$checks_total" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="비밀번호 주기(13주 이하) 및 최소 길이(8자 이상) 정책이 설정됨"
            elif [ "$ok_count" -eq 0 ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 주기·최소 길이 정책이 설정되어 있지 않음"
            else
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="일부 정책만 설정됨 — 수동 확인 필요"
            fi
            CHECK_EVIDENCE="$evidence"
            ;;
        hpux)
            # 표준 모드: /etc/default/security PASSWORD_MIN_LENGTH. Trusted Mode는 그 대신
            # /tcb/files/auth/system/default 에 u_minlen 등이 있다(둘 중 존재하는 쪽을 확인).
            defsec="/etc/default/security"
            tcbdef="/tcb/files/auth/system/default"
            evidence=""; ok_count=0; checks_total=0
            if [ -f "$defsec" ]; then
                minlen=$(grep -E '^[[:space:]]*PASSWORD_MIN_LENGTH=' "$defsec" 2>/dev/null | tail -n1 | sed -E 's/.*=//')
                evidence="$defsec: PASSWORD_MIN_LENGTH=${minlen:-미설정}"
                checks_total=1
                [ -n "$minlen" ] && [ "$minlen" -ge 8 ] 2>/dev/null && ok_count=$((ok_count + 1))
            elif [ -f "$tcbdef" ]; then
                minlen=$(grep -E ':u_minlen#' "$tcbdef" 2>/dev/null | sed -E 's/.*u_minlen#([0-9]+).*/\1/')
                evidence="$tcbdef(Trusted Mode): u_minlen=${minlen:-미설정}"
                checks_total=1
                [ -n "$minlen" ] && [ "$minlen" -ge 8 ] 2>/dev/null && ok_count=$((ok_count + 1))
            fi
            if [ "$checks_total" -eq 0 ]; then
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="$defsec / $tcbdef 를 찾을 수 없어 자동 판정 불가"
            elif [ "$ok_count" -eq "$checks_total" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="비밀번호 최소 길이(8자 이상) 정책이 설정됨"
            else
                CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 최소 길이 정책이 설정되어 있지 않음"
            fi
            CHECK_EVIDENCE="$evidence"
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}

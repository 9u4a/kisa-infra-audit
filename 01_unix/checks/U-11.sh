# U-11 (하) 사용자 shell 점검
# 판단 기준(가이드 원문): 양호 = 로그인이 불필요한 계정에 /bin/false(/sbin/nologin) 쉘이 부여된 경우
#                        취약 = 부여되지 않은 경우
# 대상(가이드 원문 목록): daemon, bin, sys, adm, listen, nobody, nobody4, noaccess, diag, operator,
#                         games, gopher  (admin 은 제외)
# 전 Unix 계열 공통 로직.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    target_accounts="daemon bin sys adm listen nobody nobody4 noaccess diag operator games gopher"
    violations=""
    evidence=""
    for name in $target_accounts; do
        entry=$(grep "^${name}:" "$passwd_file" 2>/dev/null)
        [ -z "$entry" ] && continue
        shell=$(printf '%s' "$entry" | awk -F: '{print $NF}')
        evidence="$evidence
$entry"
        case "$shell" in
            */nologin|/bin/false) ;;
            *) violations="$violations $name(shell=$shell)" ;;
        esac
    done

    if [ -z "$evidence" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="점검 대상 기본 계정(daemon/bin/sys/adm 등)이 시스템에 존재하지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="로그인이 불필요한 기본 계정에 /bin/false 또는 nologin 쉘이 부여되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="로그인 쉘이 부여된(nologin/false 가 아닌) 불필요 계정이 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}

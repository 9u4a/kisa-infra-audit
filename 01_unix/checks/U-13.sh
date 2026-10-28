# U-13 (중) 안전한 비밀번호 암호화 알고리즘 사용
# 판단 기준(가이드 원문): 양호 = SHA-2 이상(SHA-256/$5$, SHA-512/$6$, yescrypt/$y$)의 안전한 알고리즘
#                        취약 = 그 외 취약한 알고리즘(MD5/$1$, DES, Blowfish/$2*$ 등) 사용
# 자동화 범위: 전 Unix 계열 공통 — /etc/login.defs ENCRYPT_METHOD 우선 확인, 없으면 /etc/shadow
#             해시 접두사로 판정.

# 진단 검수 U-R13: 예전에는 login.defs 가 SHA512 면 바로 GOOD 이라, 설정 변경 전에 만들어진 /etc/shadow 의 MD5($1$)
# 등 해시가 남아 있어도 보지 않았다. 이제 설정과 실제 해시를 모두 본다. 증적에는 해시 앞 6자(솔트 일부 포함) 대신
# 계정명과 알고리즘 식별자($1$·$6$ 등)만 남긴다(S5). login.defs 는 같은 키가 여럿이면 마지막 값이 쓰인다(주석 제외).
run_check() {
    logindefs="/etc/login.defs"
    method=""
    if [ -f "$logindefs" ]; then
        method=$(grep -E '^[[:space:]]*ENCRYPT_METHOD' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
    fi
    m_ok=""
    if [ -n "$method" ]; then
        case "$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')" in
            SHA256|SHA512|YESCRYPT) m_ok=1 ;;
            *) m_ok=0 ;;
        esac
    fi

    shadow_ok=0; weak=""; algos=""
    if [ -r /etc/shadow ]; then
        shadow_ok=1
        # 계정명:알고리즘 식별자 (해시 본문·솔트는 남기지 않음). 잠긴(! *) 계정·빈 필드는 제외.
        algos=$(awk -F: '$2 !~ /^[!*]|^$/ { id = "DES/기타"; if (match($2, /^\$[^$]+\$/)) id = substr($2, RSTART, RLENGTH); print $1 ":" id }' /etc/shadow 2>/dev/null)
        weak=$(printf '%s\n' "$algos" | grep -vE ':\$(5|6|y|gy)\$$' | sed '/^$/d')
    fi
    evd="$logindefs: ENCRYPT_METHOD ${method:-미설정}"
    [ "$shadow_ok" -eq 1 ] && evd="$evd
/etc/shadow 계정별 알고리즘:
${algos:-(비밀번호가 설정된 계정 없음)}"
    CHECK_EVIDENCE="$evd"

    if [ "$m_ok" = "0" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="login.defs ENCRYPT_METHOD=${method} 는 취약한 암호화 알고리즘임"
    elif [ -n "$weak" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="SHA-2 미만(예: MD5 \$1\$, DES, Blowfish \$2*\$)의 취약한 해시를 사용하는 계정이 존재함: $(printf '%s' "$weak" | cut -d: -f1 | tr '\n' ' ')${m_ok:+(ENCRYPT_METHOD=${method} 설정 이전에 만든 비밀번호 - 비밀번호 재설정 필요)}"
    elif [ "$shadow_ok" -eq 0 ]; then
        CHECK_STATUS="MANUAL"
        if [ "$m_ok" = "1" ]; then
            CHECK_DETAIL="login.defs ENCRYPT_METHOD=${method} (SHA-2 이상)이나 /etc/shadow 를 읽을 수 없어 기존 계정 해시는 확인하지 못함"
        else
            CHECK_DETAIL="/etc/login.defs 에 ENCRYPT_METHOD 설정이 없고 /etc/shadow 를 읽을 수 없어 자동 판정 불가"
        fi
    elif [ "$m_ok" = "1" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="login.defs ENCRYPT_METHOD=${method} (SHA-2 이상)로 설정되었고 /etc/shadow 의 해시도 모두 SHA-2/yescrypt 임"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="ENCRYPT_METHOD 설정은 없으나, /etc/shadow 의 모든 계정이 SHA-2/yescrypt(\$5\$/\$6\$/\$y\$) 해시를 사용함"
    fi
}

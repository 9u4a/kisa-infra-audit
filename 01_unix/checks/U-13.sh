# U-13 (중) 안전한 비밀번호 암호화 알고리즘 사용
# 판단 기준(가이드 원문): 양호 = SHA-2 이상(SHA-256/$5$, SHA-512/$6$, yescrypt/$y$)의 안전한 알고리즘
#                        취약 = 그 외 취약한 알고리즘(MD5/$1$, DES, Blowfish/$2*$ 등) 사용
# 자동화 범위: 전 Unix 계열 공통 — /etc/login.defs ENCRYPT_METHOD 우선 확인, 없으면 /etc/shadow
#             해시 접두사로 판정.

run_check() {
    logindefs="/etc/login.defs"
    method=""
    if [ -f "$logindefs" ]; then
        method=$(grep -E '^[[:space:]]*ENCRYPT_METHOD' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
    fi

    if [ -n "$method" ]; then
        case "$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')" in
            SHA256|SHA512|YESCRYPT)
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="login.defs ENCRYPT_METHOD=${method} (SHA-2 이상)로 설정됨"
                CHECK_EVIDENCE="$logindefs: ENCRYPT_METHOD $method"
                return
                ;;
            *)
                CHECK_STATUS="VULN"
                CHECK_DETAIL="login.defs ENCRYPT_METHOD=${method} 는 취약한 암호화 알고리즘임"
                CHECK_EVIDENCE="$logindefs: ENCRYPT_METHOD $method"
                return
                ;;
        esac
    fi

    if [ -r /etc/shadow ]; then
        weak=$(awk -F: '$2 !~ /^[!*]|^$/ {print $1":"$2}' /etc/shadow | grep -vE ':\$(5|6|y)\$' )
        sample=$(awk -F: '$2 !~ /^[!*]|^$/ {print $1":"substr($2,1,6)}' /etc/shadow)
        if [ -z "$weak" ]; then
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="ENCRYPT_METHOD 설정은 없으나, /etc/shadow 의 모든 계정이 SHA-2/yescrypt(\$5\$/\$6\$/\$y\$) 해시를 사용함"
        else
            CHECK_STATUS="VULN"
            CHECK_DETAIL="SHA-2 미만(예: MD5 \$1\$, DES, Blowfish \$2*\$)의 취약한 해시를 사용하는 계정이 존재함"
        fi
        CHECK_EVIDENCE="$sample"
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="/etc/login.defs 에 ENCRYPT_METHOD 설정이 없고 /etc/shadow 를 읽을 수 없어 자동 판정 불가"
        CHECK_EVIDENCE=""
    fi
}

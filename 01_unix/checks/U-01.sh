# U-01 (상) root 계정 원격 접속 제한
# 판단 기준(가이드 원문): 양호 = 원격터미널 서비스를 사용하지 않거나, 사용 시 root 직접 접속을 차단한 경우
#                        취약 = 원격터미널 서비스 사용 시 root 직접 접속을 허용한 경우
# 자동화 범위: SSH(sshd_config PermitRootLogin)는 SunSSH/OpenSSH 모두 동일한 문법이라 전 환경
# 공통으로 판정한다. Solaris/AIX/HP-UX 는 SSH 가 없거나 설정이 불명확할 때 각 OS 고유의
# "콘솔 전용 root 로그인" 메커니즘(telnet/rlogin 등 레거시 원격터미널에 대한 전통적 차단 수단)도
# 함께 확인한다 - 세 OS 모두 Docker 로 실기 검증할 수 없어(SPARC/POWER/PA-RISC 전용) 문서
# (Oracle Solaris 관리 가이드 §login(1)/default/login(4), IBM AIX security/user(4), HPE HP-UX
# securetty(4)) 기준으로 구현했다.

_u01_check_sshd() {
    # 반환: 0=판정 완료(그 결과를 그대로 쓸 것), 1=sshd 자체가 없어서 OS 고유 메커니즘으로 넘어가야 함
    sshd_cfg="/etc/ssh/sshd_config"
    if ! command -v sshd >/dev/null 2>&1 && [ ! -f "$sshd_cfg" ]; then
        return 1
    fi
    if [ ! -f "$sshd_cfg" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="sshd 는 설치되어 있으나 $sshd_cfg 를 찾을 수 없어 자동 판정 불가"
        CHECK_EVIDENCE=""
        return 0
    fi
    # sshd 는 같은 키워드의 "처음" 값을 쓰고 sshd_config.d 드롭인(Include)도 읽는다 - 예전처럼 본 파일의
    # 마지막 값만 보면 드롭인에서 먼저 지정된 값을 놓친다(lib/common.sh sshd_effective_value).
    sshd_effective_value PermitRootLogin
    value=$SSHD_VALUE
    evidence=$(sshd_global_lines | grep -iE '^PermitRootLogin[[:space:]]')
    [ -z "$evidence" ] && evidence="(전역 PermitRootLogin 설정 없음 → 기본값 적용)"
    overrides=$(sshd_match_overrides PermitRootLogin | grep -viE 'PermitRootLogin[[:space:]]+no([[:space:]]|$)')
    case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
        no)
            if [ -n "$overrides" ]; then
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="전역은 PermitRootLogin no 이나 Match 블록에서 root 접속을 예외 허용함 - 예외 대상의 적절성 확인 필요"
            else
                CHECK_STATUS="GOOD"; CHECK_DETAIL="PermitRootLogin no 가 적용됨"
            fi ;;
        ""|prohibit-password|without-password)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="PermitRootLogin 이 명시적으로 no 가 아님(값: '${value:-미설정, 기본값}'). 기본 정책 확인 필요" ;;
        *)
            CHECK_STATUS="VULN"; CHECK_DETAIL="PermitRootLogin ${value} 가 적용되어 root 원격 접속이 허용됨" ;;
    esac
    CHECK_EVIDENCE="판정 근거: $SSHD_VALUE_SOURCE
전역 설정(sshd 가 읽는 순서):
$evidence${overrides:+
Match 블록 예외:
$overrides}"
    return 0
}

# _u01_linux_telnet -- Telnet 이 쓰이면(프로세스·telnet.socket·xinetd·inetd) 가이드 LINUX 조치(/etc/securetty 에
# pts/* 없음 + /etc/pam.d/login 의 pam_securetty.so 활성)로 root 직접 접속 차단 여부를 본다. 결과: U01_TEL=""(미사용)
# / GOOD / VULN, U01_TEL_EVD. 진단 검수 U-R17: 예전에는 sshd 가 없으면 telnet 을 보지 않고 GOOD 이었다.
_u01_linux_telnet() {
    U01_TEL=""; U01_TEL_EVD=""
    _use=""
    command -v pgrep >/dev/null 2>&1 && [ -n "$(pgrep -f 'in\.telnetd|telnetd' 2>/dev/null)" ] && _use="프로세스"
    if command -v systemctl >/dev/null 2>&1; then
        run_to 10 systemctl is-active --quiet telnet.socket 2>/dev/null && _use="$_use telnet.socket(active)"
        case "$(run_to 10 systemctl is-enabled telnet.socket 2>/dev/null | head -n1)" in enabled*) _use="$_use telnet.socket(enabled)" ;; esac
    fi
    grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/telnet 2>/dev/null && _use="$_use xinetd"
    awk '$0 !~ /^[[:space:]]*#/ && $1 == "telnet" { f = 1 } END { exit !f }' /etc/inetd.conf 2>/dev/null && _use="$_use inetd"
    [ -n "$_use" ] || return 0
    _pts=$(grep -E '^[[:space:]]*pts/' /etc/securetty 2>/dev/null | tr '\n' ' ')
    _pam=$(grep -vE '^[[:space:]]*#' /etc/pam.d/login 2>/dev/null | grep -E 'pam_securetty\.so')
    U01_TEL_EVD="Telnet 사용 근거:$_use
/etc/securetty: $( [ -f /etc/securetty ] && echo "있음(pts 항목: ${_pts:-없음})" || echo 없음)
/etc/pam.d/login pam_securetty: ${_pam:-없음}"
    if [ -f /etc/securetty ] && [ -z "$_pts" ] && [ -n "$_pam" ]; then
        U01_TEL="GOOD"
    else
        U01_TEL="VULN"
    fi
}

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            if ! _u01_check_sshd; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="SSH 서비스(sshd)가 설치되어 있지 않아 원격 root 접속 위험이 없음"
                CHECK_EVIDENCE="command -v sshd -> not found"
            fi
            _u01_linux_telnet
            if [ "$U01_TEL" = "VULN" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="Telnet 서비스가 사용 중이며 root 직접 접속이 차단되지 않음(/etc/securetty 의 pts 항목 또는 pam_securetty 미적용) / SSH: $CHECK_DETAIL"
            elif [ "$U01_TEL" = "GOOD" ] && [ "$CHECK_STATUS" = "GOOD" ]; then
                CHECK_DETAIL="$CHECK_DETAIL / Telnet: securetty·pam_securetty 로 root 직접 접속 차단됨"
            fi
            [ -n "$U01_TEL" ] && CHECK_EVIDENCE="$CHECK_EVIDENCE
$U01_TEL_EVD"
            ;;
        solaris)
            if _u01_check_sshd; then
                return
            fi
            # SunSSH 가 없으면 전통적으로 telnet/rlogin 이 원격 접속 경로 - /etc/default/login 의
            # CONSOLE=/dev/console 설정이 "root는 콘솔에서만 로그인 가능"을 강제한다(Solaris 표준
            # 보안 강화 항목). 이 값이 없으면 root가 telnet/rlogin으로도 직접 로그인 가능하다.
            deflogin="/etc/default/login"
            if [ -f "$deflogin" ] && grep -qE '^[[:space:]]*CONSOLE=' "$deflogin" 2>/dev/null; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="SSH 없음, $deflogin 에 CONSOLE 설정이 있어 root 로그인이 콘솔로 제한됨"
                CHECK_EVIDENCE=$(grep -E '^[[:space:]]*CONSOLE=' "$deflogin")
            elif [ -f "$deflogin" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="SSH 없음, $deflogin 에 CONSOLE 설정이 없어 root가 telnet/rlogin 등으로 직접 원격 로그인 가능"
                CHECK_EVIDENCE="$deflogin 에 CONSOLE= 라인 없음"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="SSH 와 $deflogin 모두 찾지 못해 자동 판정 불가"
                CHECK_EVIDENCE=""
            fi
            ;;
        aix)
            if _u01_check_sshd; then
                return
            fi
            # AIX는 /etc/security/user 의 root 스탠자 rlogin 속성(기본값 true)이 telnet/rlogin
            # 원격 로그인 허용 여부를 결정한다. rlogin=false 면 원격 직접 로그인 차단.
            secuser="/etc/security/user"
            if [ -f "$secuser" ]; then
                rlogin_val=$(awk '
                    /^root:/ {insec=1; next}
                    /^[a-zA-Z0-9_]+:/ {insec=0}
                    insec && /rlogin[[:space:]]*=/ {print; exit}
                ' "$secuser" | sed -E 's/.*=[[:space:]]*//')
                if [ "$rlogin_val" = "false" ]; then
                    CHECK_STATUS="GOOD"
                    CHECK_DETAIL="SSH 없음, $secuser 의 root 스탠자에 rlogin=false 설정되어 원격 로그인 차단됨"
                else
                    CHECK_STATUS="VULN"
                    CHECK_DETAIL="SSH 없음, $secuser 의 root rlogin 속성이 false 로 설정되지 않음(기본값 true=허용)"
                fi
                CHECK_EVIDENCE="root rlogin=${rlogin_val:-미설정(기본값 true)}"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="SSH 와 $secuser 모두 찾지 못해 자동 판정 불가"
                CHECK_EVIDENCE=""
            fi
            ;;
        hpux)
            if _u01_check_sshd; then
                return
            fi
            # HP-UX는 /etc/securetty 가 root 로그인을 허용할 tty 목록을 제한한다(파일이 없으면
            # 제한 없음=모든 tty에서 root 로그인 허용). pts/ptty(가상/네트워크 터미널)가 목록에
            # 없어야 원격 root 직접 로그인이 차단된 것으로 본다.
            securetty="/etc/securetty"
            if [ -f "$securetty" ]; then
                pty_lines=$(grep -E '^(pts/|ptty)' "$securetty" 2>/dev/null)
                if [ -z "$pty_lines" ]; then
                    CHECK_STATUS="GOOD"
                    CHECK_DETAIL="SSH 없음, $securetty 에 가상/네트워크 터미널(pts/ptty)이 등록되어 있지 않아 원격 root 로그인 차단됨"
                    CHECK_EVIDENCE=$(cat "$securetty")
                else
                    CHECK_STATUS="VULN"
                    CHECK_DETAIL="SSH 없음, $securetty 에 가상/네트워크 터미널이 등록되어 원격 root 로그인이 허용됨"
                    CHECK_EVIDENCE="$pty_lines"
                fi
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="SSH 없음, $securetty 파일이 없어 모든 터미널에서 root 로그인이 허용됨(기본값)"
                CHECK_EVIDENCE="$securetty 파일 없음"
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}

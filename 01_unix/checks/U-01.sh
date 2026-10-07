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
    value=$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]' "$sshd_cfg" 2>/dev/null | awk '{print $2}' | tail -n1)
    evidence=$(grep -inE '^[[:space:]]*PermitRootLogin[[:space:]]' "$sshd_cfg" 2>/dev/null)
    [ -z "$evidence" ] && evidence="(PermitRootLogin 설정 없음 → 기본값 적용)"
    case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
        no)
            CHECK_STATUS="GOOD"; CHECK_DETAIL="sshd_config 에 PermitRootLogin no 설정됨" ;;
        ""|prohibit-password|without-password)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="PermitRootLogin 이 명시적으로 no 가 아님(값: '${value:-미설정, 기본값}'). 기본 정책 확인 필요" ;;
        *)
            CHECK_STATUS="VULN"; CHECK_DETAIL="sshd_config 에 PermitRootLogin ${value} 설정되어 root 원격 접속이 허용됨" ;;
    esac
    CHECK_EVIDENCE="$sshd_cfg:
$evidence"
    return 0
}

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            if ! _u01_check_sshd; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="SSH 서비스(sshd)가 설치되어 있지 않아 원격 root 접속 위험이 없음"
                CHECK_EVIDENCE="command -v sshd -> not found"
            fi
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

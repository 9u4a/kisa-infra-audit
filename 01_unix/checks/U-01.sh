# U-01 (상) root 계정 원격 접속 제한
# 판단 기준(가이드 원문): 양호 = 원격터미널 서비스를 사용하지 않거나, 사용 시 root 직접 접속을 차단한 경우
#                        취약 = 원격터미널 서비스 사용 시 root 직접 접속을 허용한 경우
# 현재 자동화 범위: LINUX(rhel/debian) 의 SSH(sshd_config) 만 판정. Telnet/Solaris/AIX/HP-UX 는 0.2.0에서 확장.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            sshd_cfg="/etc/ssh/sshd_config"
            if ! command -v sshd >/dev/null 2>&1 && [ ! -f "$sshd_cfg" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="SSH 서비스(sshd)가 설치되어 있지 않아 원격 root 접속 위험이 없음"
                CHECK_EVIDENCE="command -v sshd -> not found"
                return
            fi
            if [ ! -f "$sshd_cfg" ]; then
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="sshd_config 파일을 찾을 수 없어 자동 판정 불가"
                CHECK_EVIDENCE=""
                return
            fi
            # 주석/공백 제외, 마지막 설정값을 유효값으로 간주
            value=$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]' "$sshd_cfg" 2>/dev/null | awk '{print $2}' | tail -n1)
            evidence=$(grep -inE '^[[:space:]]*PermitRootLogin[[:space:]]' "$sshd_cfg" 2>/dev/null)
            [ -z "$evidence" ] && evidence="(PermitRootLogin 설정 없음 → 배포판 기본값 적용)"
            case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
                no)
                    CHECK_STATUS="GOOD"; CHECK_DETAIL="sshd_config 에 PermitRootLogin no 설정됨" ;;
                ""|prohibit-password|without-password)
                    CHECK_STATUS="MANUAL"
                    CHECK_DETAIL="PermitRootLogin 이 명시적으로 no 가 아님(값: '${value:-미설정, 배포판 기본값}'). 배포판 기본 정책 확인 필요" ;;
                *)
                    CHECK_STATUS="VULN"; CHECK_DETAIL="sshd_config 에 PermitRootLogin ${value} 설정되어 root 원격 접속이 허용됨" ;;
            esac
            CHECK_EVIDENCE="$sshd_cfg:
$evidence"
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (0.2.0에서 SOLARIS/AIX/HP-UX 지원 예정)"
            CHECK_EVIDENCE=""
            ;;
    esac
}

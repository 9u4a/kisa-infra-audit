# U-62 (하) 로그인 시 경고 메시지 설정 — 조치
# 변경: /etc/motd·/etc/issue 에 경고문 덧붙임(기본 문구뿐일 때), sshd Banner 없으면 /etc/issue.net 작성+Banner /etc/issue.net, telnetd 있으면 issue.net, vsftpd ftpd_banner 추가
run_fix() {
    banner_text="Authorized access only. All activity may be monitored and reported."
    applied=""

    # check(U-62)와 같은 기준(진단 검수 U-R17): 배포판 기본 문구만 있으면 경고문을 덧붙인다(기존 내용은 유지).
    for f in /etc/motd /etc/issue; do
        [ -s "$f" ] && [ "$(banner_custom_lines "$f")" -gt 0 ] && continue
        fix_backup "$f"
        printf '%s\n' "$banner_text" >> "$f"
        applied="$applied $f"
    done

    if [ -f /etc/ssh/sshd_config ]; then
        # check(U-62)와 같이 실제 적용 값(sshd -T / Include 를 펼친 첫 값)을 본다(1.5.0 A6). 배너 파일이 지정돼 있지만
        # 비었거나 배포판 기본 문구뿐이면 그 파일에 경고문을 덧붙인다.
        sshd_effective_value Banner
        line=""
        case "$SSHD_VALUE" in
            ''|none|None|NONE) : ;;
            *)
                line=$SSHD_VALUE
                if [ ! -s "$SSHD_VALUE" ] || [ "$(banner_custom_lines "$SSHD_VALUE")" -eq 0 ]; then
                    fix_backup "$SSHD_VALUE"
                    printf '%s\n' "$banner_text" >> "$SSHD_VALUE"
                    applied="$applied $SSHD_VALUE(sshd Banner 파일)"
                fi ;;
        esac
        # 주 설정 파일에는 Banner <파일> 이 있는데 적용 값이 none 이면 드롭인(sshd_config.d)이 먼저 none 을 지정한 것이다 -
        # 주 파일을 고쳐도 소용없으므로 건드리지 않고 아래 남은 부분(PARTIAL)으로 알린다.
        if [ -z "$line" ] && grep -iE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config | grep -qviE '[[:space:]]none[[:space:]]*$'; then
            line="(드롭인 none)"
        fi
        if [ -z "$line" ]; then
            fix_backup /etc/ssh/sshd_config
            # /etc/issue.net 도 덮어쓰므로 백업한다(예전에는 백업 없이 덮어써 원복 후에도 원래 내용이 사라졌다)
            fix_backup /etc/issue.net
            printf '%s\n' "$banner_text" > /etc/issue.net
            if grep -qiE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config; then
                fix_sed_inplace /etc/ssh/sshd_config -E 's#^([[:space:]]*Banner[[:space:]]+).*#\1/etc/issue.net#I'
            else
                printf 'Banner /etc/issue.net\n' >> /etc/ssh/sshd_config
            fi
            applied="$applied sshd_config(Banner /etc/issue.net)"
        fi
    fi

    if command -v telnetd >/dev/null 2>&1 || command -v in.telnetd >/dev/null 2>&1; then
        if [ ! -s /etc/issue.net ]; then
            fix_backup /etc/issue.net
            printf '%s\n' "$banner_text" > /etc/issue.net
            applied="$applied /etc/issue.net"
        fi
    fi

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        grep -qiE '^[[:space:]]*(ftpd_banner|banner_file)' "$f" && continue
        fix_backup "$f"
        printf 'ftpd_banner=%s\n' "$banner_text" >> "$f"
        applied="$applied $f(ftpd_banner)"
    done

    # 1.5.0 A6: check 는 SMTP(Postfix/Sendmail/Exim)·DNS(BIND version)·ProFTPD 배너도 본다. 이 부분은 서비스 설정 문법 검사와
    # 재시작이 필요해 자동으로 바꾸지 않는다 - 위 조치 뒤에도 check 가 미설정을 보고하면 PARTIAL(적용한 부분은 유지, 남은 부분은
    # 수동 조치)로 정직하게 돌려준다(F4). SCRIPT_DIR 은 fix.sh 의 폴더(01_unix).
    rest=""
    if [ -f "${SCRIPT_DIR:-}/checks/U-62.sh" ]; then
        rest=$( # shellcheck disable=SC1091
                . "$SCRIPT_DIR/checks/U-62.sh" && run_check >/dev/null 2>&1 && [ "$CHECK_STATUS" != "GOOD" ] && printf '%s' "$CHECK_DETAIL")
    fi

    if [ -n "$rest" ]; then
        FIX_STATUS="PARTIAL"
        FIX_DETAIL="적용:${applied:- 없음} / 남은 부분(SMTP·DNS·ProFTPD 배너는 설정 후 서비스 재시작이 필요해 수동 조치): $rest"
        FIX_EVIDENCE="$applied"
    elif [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="모든 대상에 이미 경고 메시지가 설정되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="로그온 경고 메시지를 설정함:$applied (sshd/vsftpd 는 재시작 후 적용)"; FIX_EVIDENCE="$applied"
    fi
}

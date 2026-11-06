# U-62 (하) 로그인 시 경고 메시지 설정
# 판단 기준(가이드 원문): 양호 = 서버 및 사용 중인 Telnet/FTP/SMTP/DNS 서비스에 로그온 경고 메시지 설정
#                        취약 = 미설정
# 자동화 범위: 서버 콘솔(/etc/motd, /etc/issue) + SSH(Banner) 는 항상 확인, 그 외 서비스는
#             설치된 경우에만 확인.
# 1.5.0 A6: 예전에는 SMTP 배너를 증적에만 남기고 판정하지 않았고, DNS 는 보지 않았으며, sshd 는 주 설정 파일만 봐서
#           sshd_config.d 드롭인(Include)의 Banner 를 놓쳤다. 가이드 조치 사례 기준으로
#           - SSH: 실제 적용 Banner(sshd -T, 안 되면 Include 를 펼친 첫 값 - sshd_effective_value) + 배너 파일 내용
#           - SMTP: Postfix smtpd_banner·Sendmail SmtpGreetingMessage·Exim smtp_banner 가 배포 기본값(버전·제품명 노출)이 아님
#           - DNS: BIND options 의 version 문(버전 대신 문구 응답)
#           - FTP: vsftpd ftpd_banner/banner_file, ProFTPD DisplayLogin
#           을 본다. 설정 조회 명령이 실패·시간 초과하면 "확인 못 함"으로 모아 ERROR 로 둔다(S6, 미설정 근거가 있으면 VULN).

run_check() {
    missing=""
    unverified=""
    evidence=""

    for f in /etc/motd /etc/issue; do
        if [ -s "$f" ] && [ "$(banner_custom_lines "$f")" -gt 0 ]; then
            evidence="$evidence
$f: 설정됨 (배포판 기본 문구 외 내용 있음)"
        elif [ -s "$f" ]; then
            # 진단 검수 U-R17: 배포판 기본 문구만 있는 파일은 경고문으로 인정하지 않는다(lib/common.sh banner_custom_lines)
            missing="$missing $f(배포판 기본 문구뿐)"
        else
            missing="$missing $f(없음/비어있음)"
        fi
    done

    if [ -f /etc/ssh/sshd_config ]; then
        sshd_effective_value Banner
        evidence="$evidence
sshd Banner: ${SSHD_VALUE:-미설정} [$SSHD_VALUE_SOURCE]"
        case "$SSHD_VALUE" in
            ''|none|None|NONE) missing="$missing sshd(Banner 미설정)" ;;
            *)
                if [ ! -s "$SSHD_VALUE" ]; then
                    missing="$missing sshd(Banner 파일 $SSHD_VALUE 없음/비어있음)"
                elif [ "$(banner_custom_lines "$SSHD_VALUE")" -eq 0 ]; then
                    missing="$missing sshd(Banner 파일 $SSHD_VALUE 배포판 기본 문구뿐)"
                fi ;;
        esac
    fi

    if command -v in.telnetd >/dev/null 2>&1 || command -v telnetd >/dev/null 2>&1; then
        if [ -s /etc/issue.net ]; then
            evidence="$evidence
/etc/issue.net: 설정됨"
        else
            missing="$missing telnet(/etc/issue.net 없음/비어있음)"
        fi
    fi

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*(ftpd_banner|banner_file)' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f banner: ${line:-미설정}"
        [ -z "$line" ] && missing="$missing vsftpd(배너 미설정)"
    done
    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*DisplayLogin[[:space:]]' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f DisplayLogin: ${line:-미설정}"
        [ -z "$line" ] && missing="$missing proftpd(DisplayLogin 미설정)"
    done

    # ---- SMTP ----
    # Postfix 기본값 "$myhostname ESMTP $mail_name" 은 제품명을 알리는 기본 응답이지 경고 메시지가 아니다.
    if command -v postconf >/dev/null 2>&1; then
        banner=$(run_to 15 postconf -h smtpd_banner 2>/dev/null)
        rc=$?
        evidence="$evidence
postfix smtpd_banner: ${banner:-조회 실패}"
        if [ "$rc" -ne 0 ] || [ -z "$banner" ]; then
            unverified="$unverified postfix(postconf 조회 실패)"
        else
            case "$banner" in
                *'$mail_name'*|*'$mail_version'*) missing="$missing postfix(smtpd_banner 기본값)" ;;
            esac
        fi
    fi
    # Sendmail 기본 SmtpGreetingMessage 는 "$j Sendmail $v/$Z; $b"(버전 매크로) - 버전 매크로가 남았거나 줄이 없으면 미설정
    if [ -f /etc/mail/sendmail.cf ]; then
        line=$(grep -E '^O[[:space:]]*SmtpGreetingMessage[[:space:]]*=' /etc/mail/sendmail.cf 2>/dev/null | tail -n1)
        evidence="$evidence
sendmail.cf SmtpGreetingMessage: ${line:-미설정}"
        case "$line" in
            '') missing="$missing sendmail(SmtpGreetingMessage 미설정)" ;;
            *'$v'*|*'$Z'*) missing="$missing sendmail(SmtpGreetingMessage 기본값 - 버전 노출)" ;;
        esac
    fi
    # Exim 기본 smtp_banner 는 "${primary_hostname} ESMTP Exim ${version_number} ..." - 버전 변수가 남았으면 미설정
    exim_bin=""
    for b in exim4 exim; do command -v "$b" >/dev/null 2>&1 && { exim_bin=$b; break; }; done
    if [ -n "$exim_bin" ]; then
        ev=$(run_to 15 "$exim_bin" -bP smtp_banner 2>/dev/null)
        rc=$?
        val=$(printf '%s\n' "$ev" | sed -n 's/^[[:space:]]*smtp_banner[[:space:]]*=[[:space:]]*//p' | head -n1)
        evidence="$evidence
$exim_bin -bP smtp_banner: ${val:-조회 실패}"
        if [ "$rc" -ne 0 ] || [ -z "$val" ]; then
            unverified="$unverified exim(smtp_banner 조회 실패)"
        else
            case "$val" in *version_number*) missing="$missing exim(smtp_banner 기본값 - 버전 노출)" ;; esac
        fi
    fi

    # ---- DNS(BIND) ----
    # 가이드 기준은 "사용 중인" 서비스 - BIND(named)가 설치되어 있거나 실행 중일 때만 본다(설정 파일만 남은 경우 제외)
    named_conf=""
    if command -v named >/dev/null 2>&1 || [ -n "$(proc_match_pids '^named$' 2>/dev/null)" ]; then
        for f in /etc/named.conf /etc/bind/named.conf; do
            [ -f "$f" ] && { named_conf=$f; break; }
        done
        [ -n "$named_conf" ] || unverified="$unverified named(설정 파일 위치를 찾지 못함)"
    fi
    if [ -n "$named_conf" ]; then
        # include 를 따라가 주석을 지운 본문에서 options 블록의 version 문을 찾는다(lib/common.sh named_conf_flatten 은
        # 정해진 키워드만 내므로, 여기서는 읽은 파일 목록만 쓰고 version 문은 주석을 뺀 각 파일에서 찾는다)
        recs=$(named_conf_flatten "$named_conf")
        unread=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "!unread" { printf "%s ", $2 }')
        ver=""
        for nf in $(printf '%s\n' "$recs" | awk -F'\t' '$1 == "@file" { print $2 }'); do
            v=$(sed -e 's#//.*##' -e 's/#.*//' "$nf" 2>/dev/null | grep -E '(^|[[:space:];{])version[[:space:]]+"[^"]*"' | head -n1)
            [ -n "$v" ] && { ver="$nf: $(printf '%s' "$v" | sed 's/^[[:space:]]*//')"; break; }
        done
        evidence="$evidence
BIND($named_conf) version 문: ${ver:-미설정}"
        if [ -z "$ver" ]; then
            if [ -n "$unread" ]; then unverified="$unverified named(include 파일 읽기 실패: $unread)"
            else missing="$missing named(options version 미설정)"; fi
        fi
    fi

    if [ -n "$missing" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="로그온 경고 메시지가 설정되지 않은 항목이 있음:$missing"
        [ -n "$unverified" ] && CHECK_DETAIL="$CHECK_DETAIL / 확인 못 함:$unverified"
    elif [ -n "$unverified" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="일부 서비스의 경고 메시지 설정을 확인하지 못함:$unverified"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="서버 콘솔/SSH 및 설치된 서비스(Telnet/FTP/SMTP/DNS)에 로그온 경고 메시지가 설정되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}

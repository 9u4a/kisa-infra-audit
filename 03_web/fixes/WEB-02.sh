# WEB-02 (상) 취약한 비밀번호 사용 제한 — 조치 [fix: confirm]
# 대상: Tomcat 전용(checks/WEB-02.sh 참고). 취약 판정된 manager-gui 계정의 비밀번호를 바꾼다.
# 1.3.0: 무작위 비밀번호 생성을 폐지했다(아무도 새 값을 몰라 배포 파이프라인·관리 접속이 끊겼음).
# 계정마다 사전 승인 + 운영자가 새 비밀번호를 터미널에서 직접 입력한다(lib/common.sh
# fix_read_new_password). 비대화형이면 바꾸지 않는다. 새 비밀번호는 XML 이스케이프해 해당 <user> 요소의
# password 속성에만 넣고(주석 속 예시·다른 계정은 건드리지 않음), awk 에는 인자가 아닌 환경변수로 넘겨
# ps 에 노출하지 않는다. 원복은 백업 파일(원래 비밀번호)로 가능하다.
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac

    # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
    tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
    f="$tcdir/tomcat-users.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    # checks/WEB-01.sh 와 같은 방식: 주석 제거 후 따옴표 속성 단위로 <user> 요소를 잘라낸다
    elems=$(strip_xml_comments "$f" | tr '\n' ' ' | \
        grep -oE '<user([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*"[^"]*")*[[:space:]]*/?>' | \
        grep -E 'roles="[^"]*manager-gui')
    if [ -z "$elems" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="manager-gui 계정이 없음"; FIX_EVIDENCE=""
        return
    fi

    weak_users=""
    old_ifs=$IFS; IFS='
'
    for e in $elems; do
        IFS=$old_ifs
        user=$(printf '%s' "$e" | sed -nE 's/.*username="([^"]*)".*/\1/p')
        pass=$(printf '%s' "$e" | sed -nE 's/.*password="([^"]*)".*/\1/p')
        if [ -n "$user" ] && { [ "${#pass}" -lt 8 ] || [ "$pass" = "$user" ] || \
             printf '%s' "$pass" | grep -qiE '^(admin|admin123|123admin|password|tomcat)$'; }; then
            weak_users="$weak_users $user"
        fi
        IFS='
'
    done
    IFS=$old_ifs
    pass=""
    if [ -z "$weak_users" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="취약 비밀번호로 판정된 계정이 없음"; FIX_EVIDENCE=""
        return
    fi
    if ! fix_tty_available; then
        FIX_STATUS="ERROR"; FIX_DETAIL="새 비밀번호는 운영자가 터미널에서 직접 입력해야 함 - 비대화형 실행이라 변경하지 않음(대상:$weak_users)"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$f"
    changed=""; skipped=""; failed=""
    for user in $weak_users; do
        if fix_confirm_tty "  Tomcat manager 계정 '$user' 의 비밀번호가 취약합니다. 지금 바꿀까요? (배포 도구·스크립트에 저장된 비밀번호도 함께 바꿔야 함)" \
           && fix_read_new_password "Tomcat '$user'"; then
            if KISA_USER="$user" KISA_NEWPW="$FIX_NEW_PASSWORD" awk '
                function xesc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
                function fixseg(s,    out, e, re, pw, u) {
                    re = "<user([ \t]+[A-Za-z_:.-]+[ \t]*=[ \t]*\"[^\"]*\")*[ \t]*/?>"
                    u = "username=\"" ENVIRON["KISA_USER"] "\""
                    out = ""
                    while (match(s, re)) {
                        e = substr(s, RSTART, RLENGTH)
                        if (index(e, u) && e ~ /roles="[^"]*manager-gui/ && match(e, /password="[^"]*"/)) {
                            pw = xesc(ENVIRON["KISA_NEWPW"])
                            e = substr(e, 1, RSTART - 1) "password=\"" pw "\"" substr(e, RSTART + RLENGTH)
                            cnt++
                        }
                        out = out substr(s, 1, RSTART - 1) e
                        s = substr(s, RSTART + RLENGTH)
                    }
                    return out s
                }
                {
                    line = $0; out = ""
                    while (line != "") {
                        if (incomment) {
                            p = index(line, "-->")
                            if (!p) { out = out line; line = ""; break }
                            out = out substr(line, 1, p + 2); line = substr(line, p + 3); incomment = 0; continue
                        }
                        p = index(line, "<!--")
                        if (!p) { out = out fixseg(line); line = ""; break }
                        out = out fixseg(substr(line, 1, p - 1)); line = substr(line, p); incomment = 1
                    }
                    print out
                }
                END { exit(cnt > 0 ? 0 : 1) }
            ' "$f" > "$f.kisa_tmp"; then
                fix_write_back "$f.kisa_tmp" "$f"
                changed="$changed $user"
            else
                rm -f "$f.kisa_tmp"
                failed="$failed $user(요소가 여러 줄에 걸쳐 자동 변경 불가 - 수동 조치)"
            fi
            FIX_NEW_PASSWORD=""
        else
            skipped="$skipped $user"
        fi
    done

    if [ -n "$changed" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="운영자가 입력한 새 비밀번호로 교체함:$changed${skipped:+ / 건너뜀:$skipped}${failed:+ / 실패:$failed} (비밀번호는 기록하지 않음, Tomcat 재시작 후 적용)"
        FIX_EVIDENCE="교체된 계정:$changed"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="변경하지 않음${skipped:+ - 건너뜀:$skipped}${failed:+ - 실패:$failed}"
        FIX_EVIDENCE=""
    fi
}

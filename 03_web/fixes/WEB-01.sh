# WEB-01 (상) Default 관리자 계정명 변경 — 조치 [fix: auto]
# 대상: Tomcat 전용(checks/WEB-01.sh 참고). manager-gui 역할 계정명이 admin/tomcat 이면
# 무작위 접미사를 붙인 새 이름으로 변경한다(어떤 이름이 "적절한지"는 조직마다 다르지만,
# 무작위 문자열은 스크립트가 안전하게 만들어낼 수 있는 값이라 U-28류 문제가 아니다).
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac

    home=$(tomcat_home)
    f="$home/conf/tomcat-users.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    # checks/WEB-01.sh 와 같은 방식(따옴표 속성 단위 요소 매칭)으로 찾는다 - 예전 '[^/]*' 정규식은
    # 비밀번호에 '/' 가 있으면 계정을 놓쳤다.
    default_user=$(strip_xml_comments "$f" | tr '\n' ' ' | \
        grep -oE '<user([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*"[^"]*")*[[:space:]]*/?>' | \
        grep -E 'roles="[^"]*manager-gui' | grep -oE 'username="(admin|tomcat)"' | head -n1 | sed -E 's/username="([^"]*)"/\1/')
    if [ -z "$default_user" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="기본값(admin/tomcat) 계정명을 가진 manager-gui 계정이 없음"; FIX_EVIDENCE=""
        return
    fi

    suffix=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-8)
    [ -z "$suffix" ] && suffix=$(date +%s | tail -c 8)
    new_user="webadmin_${suffix}"

    fix_backup "$f"
    # 주석(<!-- -->) 밖의, manager-gui 역할을 가진 <user> 요소의 username 만 바꾼다 - 예전 sed 는 파일의
    # 같은 username 을 전부(주석 속 예시, manager 권한 없는 동명 계정 포함) 바꿨다. 한 줄에 다 들어
    # 있지 않은 요소는 안전하게 바꿀 수 없어 0건이면 수동 조치로 안내한다(fix.sh 가 원복).
    awk -v old="$default_user" -v new="$new_user" '
        function fixseg(s,    out, e, re) {
            re = "<user([ \t]+[A-Za-z_:.-]+[ \t]*=[ \t]*\"[^\"]*\")*[ \t]*/?>"
            out = ""
            while (match(s, re)) {
                e = substr(s, RSTART, RLENGTH)
                if (index(e, "username=\"" old "\"") && e ~ /roles="[^"]*manager-gui/) {
                    sub("username=\"" old "\"", "username=\"" new "\"", e); cnt++
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
    ' "$f" > "$f.kisa_tmp"
    if [ $? -ne 0 ]; then
        rm -f "$f.kisa_tmp"
        FIX_STATUS="ERROR"; FIX_DETAIL="'$default_user' manager-gui 계정 요소가 여러 줄에 걸쳐 있어 안전하게 자동 변경할 수 없음 - 수동 조치 필요"; FIX_EVIDENCE=""
        return
    fi
    fix_write_back "$f.kisa_tmp" "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Tomcat manager-gui 계정명을 '$default_user' 에서 '$new_user' 로 변경함"
    FIX_EVIDENCE="변경 후 계정명: $new_user"
}

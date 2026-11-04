# WEB-01 (상) Default 관리자 계정명 변경 — 조치 [fix: auto]
# 변경: Tomcat tomcat-users.xml 관리 역할 계정명 admin/tomcat → webadmin_<무작위 8자리>(주석 밖 한 줄 요소만, 여러 줄이면 수동)
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

    # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
    tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
    f="$tcdir/tomcat-users.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    # checks/WEB-01.sh 와 같은 함수(관리 역할 전체, 큰/작은따옴표 속성 - 실무 적용 검증 P-04)로 찾는다
    default_user=$(tomcat_admin_user_elems "$f" | while IFS= read -r e; do xml_attr "$e" username; done | \
        grep -ixE 'admin|tomcat' | head -n1)
    if [ -z "$default_user" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="기본값(admin/tomcat) 계정명을 가진 관리 역할 계정이 없음"; FIX_EVIDENCE=""
        return
    fi

    suffix=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-8)
    [ -z "$suffix" ] && suffix=$(date +%s | tail -c 8)
    new_user="webadmin_${suffix}"

    fix_backup "$f"
    # 주석(<!-- -->) 밖의, manager-gui 역할을 가진 <user> 요소의 username 만 바꾼다 - 예전 sed 는 파일의
    # 같은 username 을 전부(주석 속 예시, manager 권한 없는 동명 계정 포함) 바꿨다. 한 줄에 다 들어
    # 있지 않은 요소는 안전하게 바꿀 수 없어 0건이면 수동 조치로 안내한다(fix.sh 가 원복).
    # \047 = 작은따옴표(awk 프로그램이 셸 작은따옴표 안이라 직접 쓸 수 없음)
    awk -v old="$default_user" -v new="$new_user" -v roles="$TOMCAT_ADMIN_ROLE_RE" '
        function fixseg(s,    out, e, re, ure) {
            re = "<user([ \t]+[A-Za-z_:.-]+[ \t]*=[ \t]*(\"[^\"]*\"|\047[^\047]*\047))*[ \t]*/?>"
            ure = "[ \t]username[ \t]*=[ \t]*(\"" old "\"|\047" old "\047)"
            out = ""
            while (match(s, re)) {
                e = substr(s, RSTART, RLENGTH)
                if (e ~ ure && e ~ ("[ \t]roles[ \t]*=[ \t]*(\"[^\"]*|\047[^\047]*)" roles)) {
                    sub(ure, " username=\"" new "\"", e); cnt++
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
        FIX_STATUS="ERROR"; FIX_DETAIL="'$default_user' 관리 역할 계정 요소가 여러 줄에 걸쳐 있어 안전하게 자동 변경할 수 없음 - 수동 조치 필요"; FIX_EVIDENCE=""
        return
    fi
    fix_write_back "$f.kisa_tmp" "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Tomcat 관리 역할 계정명을 '$default_user' 에서 '$new_user' 로 변경함"
    FIX_EVIDENCE="변경 후 계정명: $new_user"
}

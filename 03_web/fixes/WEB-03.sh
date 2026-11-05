# WEB-03 (상) 비밀번호 파일 권한 관리 — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 변경: Tomcat tomcat-users.xml 권한 600, 소유자 root/tomcat 이면 유지(그 외는 tomcat, root:<실행 계정 그룹> 이면 그 계정으로 변경)
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
    owner=$(stat -L -c '%U' "$f" 2>/dev/null)
    case "$owner" in
        root|tomcat) : ;;
        *) owner="tomcat" ;;
    esac
    # 1.5.0 C2: RHEL 패키지는 root:tomcat 640 으로 배포해 Tomcat(tomcat 계정)이 그룹 권한으로 읽는다 - 소유자 root 그대로 600 이면
    # Tomcat 이 파일을 못 읽어 UserDatabase 로드에 실패한다. 소유자가 root 이고 그룹이 실행 계정 이름(같은 이름의 사용자가 있음)이면
    # 소유자를 그 계정으로 넘긴 뒤 600 으로 한다.
    grp=$(stat -L -c '%G' "$f" 2>/dev/null)
    if [ "$owner" = root ] && [ -n "$grp" ] && [ "$grp" != root ] && id "$grp" >/dev/null 2>&1; then
        owner=$grp
    fi
    fix_set_owner_perm "$f" "$owner" 600
}

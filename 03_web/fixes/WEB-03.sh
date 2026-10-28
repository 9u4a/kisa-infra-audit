# WEB-03 (상) 비밀번호 파일 권한 관리 — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
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
    fix_set_owner_perm "$f" "$owner" 600
}

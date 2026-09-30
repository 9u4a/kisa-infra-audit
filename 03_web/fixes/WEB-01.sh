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

    default_user=$(strip_xml_comments "$f" | grep -oE 'username="(admin|tomcat)"[^/]*roles="[^"]*manager-gui[^"]*"' | head -n1 | sed -nE 's/.*username="([^"]*)".*/\1/p')
    if [ -z "$default_user" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="기본값(admin/tomcat) 계정명을 가진 manager-gui 계정이 없음"; FIX_EVIDENCE=""
        return
    fi

    suffix=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-8)
    [ -z "$suffix" ] && suffix=$(date +%s | tail -c 8)
    new_user="webadmin_${suffix}"

    fix_backup "$f"
    sed -i "s/username=\"$default_user\"/username=\"$new_user\"/" "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Tomcat manager-gui 계정명을 '$default_user' 에서 '$new_user' 로 변경함"
    FIX_EVIDENCE="변경 후 계정명: $new_user"
}

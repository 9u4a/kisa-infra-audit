# WEB-01 (상) Default 관리자 계정명 변경
# 판단 기준(가이드 원문): 양호 = 관리자 페이지 미사용 또는 계정명이 기본값이 아님
#                        취약 = 계정명이 기본값(Tomcat: tomcat/admin, JEUS: administrator)이거나 추측 쉬운 계정명
# 대상: Tomcat, JEUS. 자동화 범위: Tomcat tomcat-users.xml 의 manager-gui 역할 계정명.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/tomcat-users.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="tomcat-users.xml 이 없어 관리자 페이지를 사용하지 않는 것으로 판단"; CHECK_EVIDENCE=""
                return
            fi
            mgr_users=$(strip_xml_comments "$f" | grep -oE 'username="[^"]*"[^/]*roles="[^"]*manager-gui[^"]*"')
            if [ -z "$mgr_users" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="manager-gui 역할을 가진 계정이 없어 관리자 페이지 미사용"; CHECK_EVIDENCE="$f 확인"
                return
            fi
            default_hit=$(printf '%s' "$mgr_users" | grep -iE 'username="(admin|tomcat)"')
            CHECK_EVIDENCE="$mgr_users"
            if [ -n "$default_hit" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="Tomcat manager-gui 계정명이 기본값(admin/tomcat)으로 설정됨"
            else
                CHECK_STATUS="GOOD"; CHECK_DETAIL="Tomcat manager-gui 계정명이 기본값이 아님"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

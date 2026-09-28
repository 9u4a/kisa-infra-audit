# WEB-03 (상) 비밀번호 파일 권한 관리
# 판단 기준(가이드 원문): 양호 = 비밀번호 파일 권한이 600 이하 / 취약 = 600 초과
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat tomcat-users.xml.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/tomcat-users.xml"
            check_owner_perm "$f" "root tomcat" 600
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

# WEB-15 (상) 웹 서비스의 불필요한 스크립트 매핑 제거
# 판단 기준(가이드 원문): 양호 = 불필요한 스크립트 매핑이 없음 / 취약 = 존재함
# 대상: Tomcat, IIS, JEUS. "불필요 여부"는 애플리케이션 구성 지식이 필요해 자동 판정이 어렵다.
# 자동화 범위: Tomcat 의 servlet-mapping 목록을 근거로 제시하고 MANUAL 로 응답한다.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/web.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
                return
            fi
            mappings=$(strip_xml_comments "$f" | grep -A1 'servlet-name>' | grep -v '^--$')
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="등록된 servlet-mapping 목록을 근거로 불필요한 매핑 여부 수동 확인 필요"
            CHECK_EVIDENCE="$mappings"
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

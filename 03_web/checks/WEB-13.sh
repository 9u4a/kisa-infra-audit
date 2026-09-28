# WEB-13 (상) 웹 서비스 설정 파일 노출 제한
# 판단 기준(가이드 원문): 양호 = DB 연결 파일 접근 제한 + 불필요 스크립트 매핑 제거
#                        취약 = 접근 제한 미흡 또는 매핑 미제거
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat server.xml 의 DB Resource 설정 여부와 파일 권한.
# 참고: <Resource> 존재 여부로 "DB 연결 설정 있음"을 판단하는 거친 휴리스틱이라, Tomcat 기본
# UserDatabase(JNDI) 리소스처럼 실제 DB 접속정보가 없는 리소스에도 파일 권한 점검이 함께
# 트리거될 수 있다(과탐지 방향이며 실제 취약점을 놓치는 방향은 아님). 정밀 판정이 필요하면
# driverClassName/url 속성 유무까지 추가로 확인하는 후속 개선 여지가 있다.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/server.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
                return
            fi
            has_db=$(strip_xml_comments "$f" | grep -c '<Resource')
            if [ "$has_db" -eq 0 ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="DB 연결 리소스(Resource)가 설정되어 있지 않음"; CHECK_EVIDENCE="$f 에 <Resource> 없음"
                return
            fi
            check_owner_perm "$f" "root tomcat" 600
            CHECK_DETAIL="DB 연결 리소스가 설정된 server.xml 파일 권한: $CHECK_DETAIL"
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

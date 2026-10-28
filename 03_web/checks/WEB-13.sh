# WEB-13 (상) 웹 서비스 설정 파일 노출 제한
# 판단 기준(가이드 원문): 양호 = DB 연결 파일 접근 제한 + 불필요 스크립트 매핑 제거
#                        취약 = 접근 제한 미흡 또는 매핑 미제거
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat server.xml·context.xml 의 Resource 설정 여부와 파일 권한(600).
# 참고: <Resource> 존재 여부로 "DB 연결 설정 있음"을 판단하는 거친 휴리스틱이라, Tomcat 기본
# UserDatabase(JNDI) 리소스처럼 실제 DB 접속정보가 없는 리소스에도 파일 권한 점검이 함께
# 트리거될 수 있다(과탐지 방향이며 실제 취약점을 놓치는 방향은 아님).
# DB 연결 정보(JNDI DataSource)는 conf/context.xml 에 두는 경우가 많아 함께 본다(진단 검수 WEB-R11).

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            errors=""
            if ! web_load_tomcat_conf server.xml; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="server.xml 을 확인하지 못함:$errors"; CHECK_EVIDENCE=""
                return
            fi
            files=""
            for f in "$TC_FILE" "$(dirname "$TC_FILE")/context.xml"; do
                [ -f "$f" ] || continue
                if [ ! -r "$f" ]; then
                    CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 를 읽을 수 없음(권한 부족)"; CHECK_EVIDENCE=""
                    return
                fi
                [ "$(strip_xml_comments "$f" | grep -c '<Resource')" -gt 0 ] && files="$files $f"
            done
            if [ -z "$files" ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="DB 연결 리소스(Resource)가 설정되어 있지 않음"; CHECK_EVIDENCE="server.xml·context.xml 에 <Resource> 없음"
                return
            fi
            st="GOOD"; det=""; ev=""
            for f in $files; do
                check_owner_perm "$f" "root tomcat tomcat8 tomcat9 tomcat10" 600
                det="$det / $CHECK_DETAIL"; ev="$ev
$CHECK_EVIDENCE"
                case "$CHECK_STATUS" in
                    VULN) st="VULN" ;;
                    ERROR) [ "$st" = "VULN" ] || st="ERROR" ;;
                esac
            done
            CHECK_STATUS=$st
            CHECK_DETAIL="DB 연결 리소스가 설정된 파일 권한:${det# /}"
            CHECK_EVIDENCE=$ev
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

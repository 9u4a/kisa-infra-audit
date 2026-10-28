# WEB-01 (상) Default 관리자 계정명 변경
# 판단 기준(가이드 원문): 양호 = 관리자 페이지 미사용 또는 계정명이 기본값이 아님
#                        취약 = 계정명이 기본값(Tomcat: tomcat/admin, JEUS: administrator)이거나 추측 쉬운 계정명
# 대상: Tomcat, JEUS. 자동화 범위: Tomcat tomcat-users.xml 의 manager-gui 역할 계정명.
# Tomcat 이 감지됐는데 설치 경로(conf 폴더)를 못 찾으면 "관리자 페이지 미사용(GOOD)"이 아니라 ERROR(진단 검수 WEB-R3).

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            if ! confdir=$(tomcat_conf_dir); then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="Tomcat 이 감지됐으나 설치 경로(CATALINA_BASE)·conf 폴더를 찾지 못해 관리자 계정을 확인하지 못함"; CHECK_EVIDENCE=""
                return
            fi
            f="$confdir/tomcat-users.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="tomcat-users.xml 이 없어 관리자 페이지를 사용하지 않는 것으로 판단"; CHECK_EVIDENCE="$f 없음"
                return
            fi
            if [ ! -r "$f" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 를 읽을 수 없음(권한 부족) - 관리자 계정 확인 불가"; CHECK_EVIDENCE=""
                return
            fi
            # <user .../> 요소 단위로 잘라 username 속성만 남긴다 - 속성 사이를 통째로 잡으면
            # password="..." 원문까지 증적에 실려 평문 관리자 비밀번호가 결과물에 남는다.
            # 요소는 따옴표 속성 단위로 매칭한다(비밀번호에 '>' 가 있어도 요소가 잘리지 않게).
            mgr_users=$(strip_xml_comments "$f" | tr '\n' ' ' | \
                grep -oE '<user([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*"[^"]*")*[[:space:]]*/?>' | \
                grep -E 'roles="[^"]*manager-gui' | grep -oE 'username="[^"]*"')
            if [ -z "$mgr_users" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="manager-gui 역할을 가진 계정이 없어 관리자 페이지 미사용"; CHECK_EVIDENCE="$f 확인"
                return
            fi
            default_hit=$(printf '%s' "$mgr_users" | grep -iE 'username="(admin|tomcat)"')
            CHECK_EVIDENCE="$f
$mgr_users"
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

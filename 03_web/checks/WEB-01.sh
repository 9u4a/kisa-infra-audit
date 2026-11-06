# WEB-01 (상) Default 관리자 계정명 변경
# 판단 기준(가이드 원문): 양호 = 관리자 페이지 미사용 또는 계정명이 기본값이 아님
#                        취약 = 계정명이 기본값(Tomcat: tomcat/admin, JEUS: administrator)이거나 추측 쉬운 계정명
# 대상: Tomcat, JEUS. 자동화 범위: Tomcat tomcat-users.xml 의 관리 역할 계정명이 기본값 또는 추측하기 쉬운 이름 목록과 일치하는지.
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
            # 관리 역할(manager-*/admin-*) <user> 요소에서 username 속성만 남긴다 - 요소를 통째로 남기면 password 원문까지
            # 증적에 실린다(S5). 작은따옴표 속성·manager-gui 외 관리 역할도 본다(실무 적용 검증 P-04, lib/common.sh).
            elems=$(tomcat_admin_user_elems "$f")
            if [ -z "$elems" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="관리 역할(manager-gui/script/jmx/status, admin-gui/script)을 가진 계정이 없어 관리자 페이지 미사용"; CHECK_EVIDENCE="$f 확인"
                return
            fi
            mgr_users=$(printf '%s\n' "$elems" | while IFS= read -r e; do
                printf 'username=%s\n' "$(xml_attr "$e" username)"
            done)
            # 1.5.0 A23: 가이드 취약 기준의 "추측하기 쉬운 문자 조합" 도 본다 - 예전에는 admin/tomcat 만 봐 manager·robot·root 같은
            # 계정명이 GOOD 이었다(목록은 lib/common_web.sh TOMCAT_GUESSABLE_ADMIN_RE, guide.json deviation 참고)
            default_hit=$(printf '%s\n' "$mgr_users" | grep -ixE "username=($TOMCAT_DEFAULT_ADMIN_RE)")
            guess_hit=$(printf '%s\n' "$mgr_users" | grep -ixE "username=($TOMCAT_GUESSABLE_ADMIN_RE)")
            CHECK_EVIDENCE="$f
$mgr_users"
            if [ -n "$default_hit" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="Tomcat 관리 역할 계정명이 기본값(admin/tomcat)으로 설정됨"
            elif [ -n "$guess_hit" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="Tomcat 관리 역할 계정명이 추측하기 쉬운 이름임: $(printf '%s' "$guess_hit" | sed 's/^username=//' | tr '\n' ' ')"
            else
                CHECK_STATUS="GOOD"; CHECK_DETAIL="Tomcat 관리 역할 계정명이 기본값·추측하기 쉬운 이름이 아님"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

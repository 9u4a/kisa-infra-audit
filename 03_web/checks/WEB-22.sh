# WEB-22 (하) 에러 페이지 관리
# 판단 기준(가이드 원문): 양호 = 에러 페이지가 별도로 지정됨 / 취약 = 미지정 또는 정보 노출

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""; has404=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*ErrorDocument' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
                grep -qiE '^[^#]*ErrorDocument[[:space:]]+404([[:space:]]|$)' "$f" 2>/dev/null && has404=1
            done
            evidence="$evidence
[Apache] ErrorDocument 검색: ${hit:-없음}"
            # 1.5.0 C2: RHEL 기본 welcome.conf 는 루트 URL(<LocationMatch "^/+$">) 전용 ErrorDocument 403 하나뿐인데
            # 예전에는 ErrorDocument 가 한 줄이라도 있으면 GOOD 이었다 - nginx(P-05)와 같이 404 지정을 요구한다
            if [ -z "$hit" ] || [ -z "$has404" ]; then
                violations="$violations apache"
                [ -n "$hit" ] && evidence="$evidence
[Apache] ErrorDocument 404 지정 없음(다른 상태 코드만 지정됨)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""; gaps=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*error_page' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
                for n in $(nginx_error_page_gaps "$f"); do gaps="$gaps $f:$n"; done
            done
            evidence="$evidence
[Nginx] error_page 검색: ${hit:-없음}${gaps:+
[Nginx] 404 를 지정하지 않은 error_page 블록(바깥 블록 설정을 물려받지 않음):$gaps}"
            # 실무 적용 검증 P-05: error_page 가 있는 블록마다 404 도 지정돼야 한다(lib/common.sh nginx_error_page_gaps)
            { [ -z "$hit" ] || [ -n "$gaps" ]; } && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -c '<error-page>')
            evidence="$evidence
[Tomcat] $TC_FILE error-page 요소 개수: ${hit:-0}"
            { [ -z "$hit" ] || [ "$hit" -eq 0 ]; } && violations="$violations tomcat"
        fi
    esac

    web_finish "에러 페이지가 별도로 지정되지 않은 엔진" "에러 페이지가 별도로 지정되어 있음"
}

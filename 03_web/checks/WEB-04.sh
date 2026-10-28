# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정
# 판단 기준(가이드 원문): 양호 = 디렉터리 리스팅 미설정 / 취약 = 설정됨
# Apache: 실제 로드되는 설정(Include 체인, Debian sites-enabled 포함)의 Options 에서 Indexes·+Indexes·All(Indexes 포함).
# 엔진이 감지됐는데 설정을 찾거나 읽지 못하면 ERROR(S6, 진단 검수 WEB-R1/R3/R10).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            # shellcheck disable=SC2086
            hit=$(web_apache_option_hits Indexes $WEB_FILES)
            evidence="$evidence
[Apache] Options Indexes/All 검색 결과: ${hit:-없음}"
            [ -n "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                line=$(grep -nE '^[^#]*autoindex[[:space:]]+on' "$f" 2>/dev/null)
                [ -n "$line" ] && hit="$hit
$f: $line"
            done
            evidence="$evidence
[Nginx] autoindex on 검색 결과: ${hit:-없음(기본값 off)}"
            [ -n "$hit" ] && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            line=$(strip_xml_comments "$TC_FILE" | awk '/param-name>[[:space:]]*listings/{f=1} f && /param-value/{print; f=0}' | grep -i 'true')
            evidence="$evidence
[Tomcat] $TC_FILE listings 파라미터: ${line:-false 또는 미설정(기본값)}"
            [ -n "$line" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "디렉터리 리스팅이 활성화된 엔진" "감지된 엔진에서 디렉터리 리스팅이 비활성화됨"
}

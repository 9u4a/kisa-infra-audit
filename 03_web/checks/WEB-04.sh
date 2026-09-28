# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정
# 판단 기준(가이드 원문): 양호 = 디렉터리 리스팅 미설정 / 취약 = 설정됨

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            line=$(grep -nE '^[^#]*Options[^#]*\bIndexes\b' "$f" 2>/dev/null | grep -v '\-Indexes')
            [ -n "$line" ] && hit="$hit
$f: $line"
        done
        evidence="$evidence
[Apache] Indexes 옵션 검색 결과: ${hit:-없음}"
        [ -n "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            line=$(grep -nE '^[^#]*autoindex[[:space:]]+on' "$f" 2>/dev/null)
            [ -n "$line" ] && hit="$hit
$f: $line"
        done
        evidence="$evidence
[Nginx] autoindex on 검색 결과: ${hit:-없음(기본값 off)}"
        [ -n "$hit" ] && violations="$violations nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        line=""
        if [ -f "$f" ]; then
            line=$(strip_xml_comments "$f" | awk '/param-name>listings/{f=1} f && /param-value/{print; f=0}' | grep -i 'true')
        fi
        evidence="$evidence
[Tomcat] listings 파라미터: ${line:-false 또는 미설정(기본값)}"
        [ -n "$line" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="디렉터리 리스팅이 활성화된 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="감지된 엔진에서 디렉터리 리스팅이 비활성화됨"
    fi
    CHECK_EVIDENCE="$evidence"
}

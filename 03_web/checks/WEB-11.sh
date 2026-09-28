# WEB-11 (중) 웹 서비스 경로 설정
# 판단 기준(가이드 원문): 양호 = DocumentRoot 가 업무 영역과 분리된 별도 경로 / 취약 = 기본 경로 사용
# 자동화 범위: Apache/Nginx 는 잘 알려진 기본 경로 사용 여부로 판정. Tomcat 은 appBase="webapps"
# 자체가 정상 배치 구조라 "분리 여부"를 자동 판정하기 어려워 MANUAL 로 안내한다.

run_check() {
    detect_web_engines
    violations=""
    manuals=""
    evidence=""
    checked=0
    default_paths='^/usr/local/apache2/htdocs$|^/var/www/html$|^/var/www$|^/usr/share/nginx/html$'

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        docroot=""
        [ -f "$conf" ] && docroot=$(grep -E '^[^#]*DocumentRoot' "$conf" 2>/dev/null | tail -n1 | sed -E 's/^[[:space:]]*DocumentRoot[[:space:]]+"?([^"]*)"?.*/\1/')
        evidence="$evidence
[Apache] DocumentRoot=$docroot"
        printf '%s' "$docroot" | grep -qE "$default_paths" && violations="$violations apache(기본 경로 사용)"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        root=""
        for f in $files; do
            [ -f "$f" ] || continue
            r=$(grep -E '^[^#]*[[:space:]]root[[:space:]]' "$f" 2>/dev/null | tail -n1 | sed -E 's/^[[:space:]]*root[[:space:]]+([^;]*);.*/\1/')
            [ -n "$r" ] && root="$r"
        done
        evidence="$evidence
[Nginx] root=$root"
        printf '%s' "$root" | grep -qE "$default_paths" && violations="$violations nginx(기본 경로 사용)"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        manuals="$manuals tomcat(appBase=webapps 자체는 표준 구조이므로 영역 분리 여부는 배포 구성 수동 확인 필요)"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="기본 경로를 그대로 사용 중:$violations"
    elif [ -n "$manuals" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="자동 판정이 제한적인 엔진 존재:$manuals"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="웹 경로가 기본 경로와 분리되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}

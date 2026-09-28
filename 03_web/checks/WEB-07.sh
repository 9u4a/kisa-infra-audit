# WEB-07 (중) 웹 서비스 경로 내 불필요한 파일 제거
# 판단 기준(가이드 원문): 양호 = 기본 생성 불필요 파일/디렉터리가 없음 / 취약 = 존재함

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        found=""
        for p in /usr/local/apache2/htdocs/manual /usr/local/apache2/manual /var/www/manual; do
            [ -e "$p" ] && found="$found $p"
        done
        evidence="$evidence
[Apache] 매뉴얼 디렉터리: ${found:-없음}"
        [ -n "$found" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        found=""
        for p in /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html; do
            [ -e "$p" ] && found="$found $p"
        done
        evidence="$evidence
[Nginx] 기본 웰컴/에러 페이지: ${found:-없음}"
        [ -n "$found" ] && violations="$violations nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        found=""
        for p in "$home/webapps/docs" "$home/webapps/examples" "$home/webapps/host-manager" "$home/webapps/ROOT/RELEASE-NOTES.txt"; do
            [ -e "$p" ] && found="$found $p"
        done
        evidence="$evidence
[Tomcat] 기본 샘플/매뉴얼 경로: ${found:-없음}"
        [ -n "$found" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="기본 생성된 불필요 파일/디렉터리가 존재하는 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="기본 생성된 불필요 파일/디렉터리가 발견되지 않음"
    fi
    CHECK_EVIDENCE="$evidence"
}

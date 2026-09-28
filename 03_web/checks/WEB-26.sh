# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리/파일에 일반 사용자 접근 권한 없음
#                        취약 = 일반 사용자 접근 권한이 있음

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    check_log_dir() {
        _label=$1; _dir=$2
        [ -d "$_dir" ] || return
        checked=1
        bad=$(find "$_dir" -maxdepth 1 -type f -perm -0006 2>/dev/null | head -n 10)
        evidence="$evidence
[$_label] $_dir 내 other 읽기/쓰기 권한 파일: ${bad:-없음}"
        [ -n "$bad" ] && violations="$violations $_label"
    }

    case " $WEB_ENGINES " in *" apache "*)
        check_log_dir "Apache" "/usr/local/apache2/logs"
        check_log_dir "Apache" "/var/log/apache2"
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        check_log_dir "Nginx" "/var/log/nginx"
    esac
    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        check_log_dir "Tomcat" "$home/logs"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="로그 디렉터리를 찾지 못함 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="일반 사용자 접근 권한이 부여된 로그 파일이 있는 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="로그 디렉터리/파일에 일반 사용자 접근 권한이 없음"
    fi
    CHECK_EVIDENCE="$evidence"
}

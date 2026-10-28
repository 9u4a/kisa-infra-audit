# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리/파일에 일반 사용자 접근 권한 없음
#                        취약 = 일반 사용자 접근 권한이 있음
# "일반 사용자 접근 권한"은 기타(other) 권한 비트 중 하나라도(읽기·쓰기·실행) 있는 것으로 본다 - 가이드 조치가
# "chmod o-rwx <로그 디렉터리/파일>" 이다. 예전에는 -perm -0006(읽기와 쓰기가 둘 다 있을 때만)이라 644 로그가
# GOOD 이었고 폴더 자체 권한은 보지 않았다(진단 검수 WEB-R2). 로그 폴더는 대표 경로 + 설정의 로그 경로
# (lib/common.sh web_log_dirs, RHEL /var/log/httpd·/var/log/tomcat 포함). 엔진이 감지됐는데 로그 폴더를 하나도
# 못 찾으면 GOOD/NA 가 아니라 MANUAL, 읽지 못한 폴더는 ERROR.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    check_log_dirs() {
        _label=$1; _eng=$2
        checked=1
        _dirs=$(web_log_dirs "$_eng")
        if [ -z "$_dirs" ]; then
            _found_cfg=1
            case $_eng in
                apache) apache_conf_path >/dev/null || _found_cfg=0 ;;
                nginx) nginx_conf_path >/dev/null || _found_cfg=0 ;;
                tomcat) tomcat_home >/dev/null || _found_cfg=0 ;;
            esac
            if [ "$_found_cfg" -eq 0 ]; then
                errors="$errors $_eng(설정·설치 경로와 로그 폴더를 찾지 못함)"
            else
                manuals="$manuals $_eng(로그 폴더를 찾지 못함 - 로그 경로·권한 수동 확인 필요)"
            fi
            evidence="$evidence
[$_label] 로그 폴더를 찾지 못함"
            return
        fi
        for _d in $_dirs; do
            if [ ! -r "$_d" ] || [ ! -x "$_d" ]; then
                errors="$errors $_eng($_d 읽기 불가)"
                continue
            fi
            _bad=""
            _dp=$(stat -L -c '%a' "$_d" 2>/dev/null)
            if [ -z "$_dp" ]; then
                errors="$errors $_eng($_d 권한 확인 실패)"
                continue
            fi
            perm_exceeds "$_dp" 7770 && _bad="$_d(폴더 $_dp)"
            _files=$(find "$_d/" -maxdepth 1 -type f \( -perm -0001 -o -perm -0002 -o -perm -0004 \) 2>/dev/null | head -n 10)
            [ -n "$_files" ] && _bad="$_bad $(printf '%s' "$_files" | tr '\n' ' ')"
            evidence="$evidence
[$_label] $_d (폴더 권한 $_dp) 기타 사용자 권한이 있는 폴더/파일: ${_bad:-없음}"
            [ -n "$_bad" ] && case " $violations " in *" $_label "*) ;; *) violations="$violations $_label" ;; esac
        done
    }

    case " $WEB_ENGINES " in *" apache "*) check_log_dirs "Apache" apache ;; esac
    case " $WEB_ENGINES " in *" nginx "*) check_log_dirs "Nginx" nginx ;; esac
    case " $WEB_ENGINES " in *" tomcat "*) check_log_dirs "Tomcat" tomcat ;; esac

    web_finish "일반 사용자 접근 권한이 부여된 로그 폴더/파일이 있는 엔진" "로그 디렉터리/파일에 일반 사용자 접근 권한이 없음" \
        "로그 폴더를 찾지 못한 엔진이 있음"
}

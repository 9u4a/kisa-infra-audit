# WEB-14 (상) 웹 서비스 경로 내 파일의 접근 통제
# 판단 기준(가이드 원문): 양호 = 주요 설정 파일/디렉터리에 불필요한 접근 권한이 없음
#                        취약 = 불필요한 접근 권한이 부여됨
# 자동화 범위: 주 설정 파일 권한이 가이드 조치값 750 을 넘는 비트(그룹 쓰기, 기타 읽기·쓰기·실행)를 갖는지로 판정.
# 1.3.1 까지는 10진수로 비교해 644 가 "750 이하"로 통과했다(진단 검수 R-03) - 기타 읽기가 있는 644 는 VULN.
# 설정 파일을 찾지 못하거나 권한을 읽지 못하면 ERROR(예전에는 검사 대상이 없어 GOOD - 진단 검수 WEB-R3).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    judge_perm() {
        _label=$1; _eng=$2; _f=$3
        _perm=$(stat -L -c '%a' "$_f" 2>/dev/null)
        if [ -z "$_perm" ]; then
            errors="$errors $_eng($_f 권한 확인 실패)"
            return
        fi
        evidence="$evidence
[$_label] $_f perm=$_perm"
        perm_exceeds "$_perm" 750 && violations="$violations $_eng"
    }

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if conf=$(apache_conf_path); then judge_perm Apache apache "$conf"; else errors="$errors apache(설정 파일을 찾지 못함)"; fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if conf=$(nginx_conf_path); then judge_perm Nginx nginx "$conf"; else errors="$errors nginx(설정 파일을 찾지 못함)"; fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if confdir=$(tomcat_conf_dir) && [ -e "$confdir/web.xml" ]; then
            judge_perm Tomcat tomcat "$confdir/web.xml"
        else
            errors="$errors tomcat(conf/web.xml 을 찾지 못함)"
        fi
    esac

    web_finish "주요 설정 파일 권한이 750을 초과하는 엔진" "주요 설정 파일 권한이 750 이하로 설정됨"
}

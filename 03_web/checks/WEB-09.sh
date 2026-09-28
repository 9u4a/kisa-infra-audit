# WEB-09 (상) 웹 서비스 프로세스 권한 제한
# 판단 기준(가이드 원문): 양호 = 관리자 권한이 아닌 별도 최소 권한 계정으로 구동
#                        취약 = 관리자(root) 권한 계정으로 구동
# 자동화 범위: /proc 기반으로 직접 프로세스를 조회한다(ps/pgrep 미설치 최소 컨테이너 대응).
# Apache/Nginx 는 마스터(권한 있는 포트 바인딩용)는 root 로 남고 실제 요청을 처리하는 worker
# 자식 프로세스만 권한을 낮추는 것이 정상 설계이므로, 동일 바이너리의 프로세스 중 하나라도
# non-root 이면 GOOD 으로 판정한다 (전부 root 인 경우만 VULN).

run_check() {
    detect_web_engines
    violations=""
    unverified=""
    evidence=""
    checked=0

    check_binary_privilege_drop() {
        _label=$1; shift
        _pids=""
        for _comm in "$@"; do
            _pids="$_pids $(proc_pids_by_comm "$_comm")"
        done
        _pids=$(printf '%s\n' $_pids | grep -v '^$')
        if [ -z "$_pids" ]; then
            evidence="$evidence
[$_label] 프로세스를 찾지 못함(/proc 기준)"
            unverified="$unverified $_label"
            return
        fi
        _any_nonroot=0
        _detail=""
        for _pid in $_pids; do
            _uid=$(proc_uid "$_pid")
            _detail="$_detail pid=$_pid,uid=$_uid"
            [ "$_uid" != "0" ] && [ -n "$_uid" ] && _any_nonroot=1
        done
        evidence="$evidence
[$_label]$_detail"
        [ "$_any_nonroot" -eq 0 ] && violations="$violations $_label(전 프로세스 root)"
    }

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        check_binary_privilege_drop "Apache" httpd apache2
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        check_binary_privilege_drop "Nginx" nginx
    esac
    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        check_binary_privilege_drop "Tomcat" java
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="관리자(root) 권한으로만 구동 중인 웹 프로세스 존재:$violations"
    elif [ -n "$unverified" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="프로세스를 찾지 못해 실행 계정을 확인할 수 없음(수동 확인 필요):$unverified"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="웹 서비스 프로세스가 관리자 권한이 아닌 계정으로 구동됨"
    fi
    CHECK_EVIDENCE="$evidence"
}

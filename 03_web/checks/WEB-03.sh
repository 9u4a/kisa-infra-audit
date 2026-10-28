# WEB-03 (상) 비밀번호 파일 권한 관리
# 판단 기준(가이드 원문): 양호 = 비밀번호 파일 권한이 600 이하 / 취약 = 600 초과
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat tomcat-users.xml.
# 소유자는 root 또는 Tomcat 실행 계정(배포판 패키지의 tomcat/tomcat9/tomcat10, 실행 중 프로세스의 계정)이면
# 정상으로 본다 - 예전에는 root·tomcat 만 허용해 배포판 계정을 거짓 VULN 으로 봤다(진단 검수 WEB-R11).

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            if ! confdir=$(tomcat_conf_dir); then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="Tomcat 이 감지됐으나 설치 경로(CATALINA_BASE)·conf 폴더를 찾지 못해 비밀번호 파일을 확인하지 못함"; CHECK_EVIDENCE=""
                return
            fi
            owners="root tomcat tomcat8 tomcat9 tomcat10"
            for pid in $(tomcat_pids); do
                uid=$(proc_uid "$pid")
                [ -n "$uid" ] && owners="$owners $(awk -F: -v u="$uid" '$3 == u { print $1; exit }' /etc/passwd 2>/dev/null)"
            done
            check_owner_perm "$confdir/tomcat-users.xml" "$owners" 600
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}

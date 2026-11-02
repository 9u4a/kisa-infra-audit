# WEB-10 (상) 불필요한 프록시 설정 제한 — 조치 [fix: confirm]
# Apache 정방향(오픈) 프록시 ProxyRequests On 만 Off 로 바꾼다(checks/WEB-10.sh 의 VULN 기준과 같음, 1.4.1 Q-03).
# 역방향 프록시(ProxyPass/proxy_pass, Tomcat proxyName)는 업무 필요 여부를 스크립트가 알 수 없어 건드리지 않는다.
# 정방향 프록시를 업무에 쓰는 서버(사내 아웃바운드 프록시 등)는 서비스가 끊기므로 confirm 등급이다.
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        for f in $(apache_conf_path) $(apache_extra_confs); do
            [ -f "$f" ] || continue
            if grep -qiE '^[[:space:]]*ProxyRequests[[:space:]]+On' "$f" 2>/dev/null; then
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/^([[:space:]]*)[Pp][Rr][Oo][Xx][Yy][Rr][Ee][Qq][Uu][Ee][Ss][Tt][Ss]([[:space:]]+)[Oo][Nn]/\1ProxyRequests\2Off/'
                applied="$applied apache($f)"
            fi
        done
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="정방향 프록시를 끔(ProxyRequests On -> Off):$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="정방향 프록시(ProxyRequests On) 설정이 없음 - 역방향 프록시는 업무 필요 여부를 수동 확인"
        FIX_EVIDENCE=""
    fi
}

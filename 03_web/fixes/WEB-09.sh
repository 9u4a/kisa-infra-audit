# WEB-09 (상) 웹 서비스 프로세스 권한 제한 — 조치 [fix: confirm]
# checks/WEB-09.sh 는 /proc 상의 "실행 중인" 프로세스 UID 를 직접 확인하므로, 설정 파일만
# 고쳐서는 재검증을 통과할 수 없다(마스터 프로세스가 이미 root 로 뜬 상태이기 때문). Apache의
# "graceful"/Nginx의 "reload" 는 기존 연결을 끊지 않고 새 자식/워커 프로세스만 새 계정으로
# 재기동하는 무중단 방식이라(sshd 전체 재시작과 달리 관리 세션에 영향이 없음 - xinetd reload
# 와 동일한 안전성 논리), 설정 변경 직후 함께 수행한다. Tomcat 은 OS 계정 전환이 systemd 유닛
# (User=)의 몫이라 이 도구의 설정 파일 범위 밖 — MANUAL 로 남긴다.
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    candidate_user() {
        for u in www-data apache nginx http daemon; do
            if getent passwd "$u" >/dev/null 2>&1 || grep -q "^$u:" /etc/passwd 2>/dev/null; then
                echo "$u"; return
            fi
        done
        echo "daemon"
    }

    case " $WEB_ENGINES " in *" apache "*)
        pids=$(proc_pids_by_comm httpd)
        [ -z "$pids" ] && pids=$(proc_pids_by_comm apache2)
        any_nonroot=0
        for pid in $pids; do
            [ "$(proc_uid "$pid")" != "0" ] && any_nonroot=1
        done
        if [ -n "$pids" ] && [ "$any_nonroot" -eq 0 ]; then
            conf=$(apache_conf_path)
            u=$(candidate_user)
            if [ -f "$conf" ]; then
                fix_backup "$conf"
                if grep -qE '^[[:space:]]*User[[:space:]]' "$conf"; then
                    sed -i -E "s/^[[:space:]]*User[[:space:]]+.*/User $u/" "$conf"
                else
                    printf '\nUser %s\nGroup %s\n' "$u" "$u" >> "$conf"
                fi
                if command -v apachectl >/dev/null 2>&1; then
                    apachectl graceful 2>/dev/null
                elif command -v apache2ctl >/dev/null 2>&1; then
                    apache2ctl graceful 2>/dev/null
                elif command -v systemctl >/dev/null 2>&1; then
                    systemctl reload httpd 2>/dev/null || systemctl reload apache2 2>/dev/null
                fi
                applied="$applied apache(User=$u, graceful reload)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        pids=$(proc_pids_by_comm nginx)
        any_nonroot=0
        for pid in $pids; do
            [ "$(proc_uid "$pid")" != "0" ] && any_nonroot=1
        done
        if [ -n "$pids" ] && [ "$any_nonroot" -eq 0 ]; then
            conf=$(nginx_conf_path)
            u=$(candidate_user)
            if [ -f "$conf" ]; then
                fix_backup "$conf"
                if grep -qE '^[[:space:]]*user[[:space:]]' "$conf"; then
                    sed -i -E "s/^[[:space:]]*user[[:space:]]+.*/user $u;/" "$conf"
                else
                    sed -i "1i user $u;" "$conf"
                fi
                if command -v nginx >/dev/null 2>&1; then
                    nginx -s reload 2>/dev/null
                elif command -v systemctl >/dev/null 2>&1; then
                    systemctl reload nginx 2>/dev/null
                fi
                applied="$applied nginx(user=$u, reload)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        pids=$(proc_pids_by_comm java)
        any_nonroot=0
        for pid in $pids; do
            [ "$(proc_uid "$pid")" != "0" ] && any_nonroot=1
        done
        if [ -n "$pids" ] && [ "$any_nonroot" -eq 0 ]; then
            manual_only="$manual_only tomcat(OS 계정 전환은 systemd 유닛 User= 설정 필요 - 이 도구 범위 밖)"
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="웹 프로세스를 최소 권한 계정으로 전환함:$applied${manual_only:+ / 수동 조치 필요:$manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요:$manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="이미 root 가 아닌 프로세스가 확인되거나 대상 프로세스를 찾지 못함"
        FIX_EVIDENCE=""
    fi
}

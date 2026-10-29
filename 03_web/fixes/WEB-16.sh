# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        # checks/WEB-16.sh 와 같은 기준: 실제 로드 순서상 마지막 ServerTokens 가 Prod 여야 한다. 메인 설정 끝에
        # 붙이면 모든 Include(Debian conf-enabled/security.conf 포함)보다 뒤라 마지막 값이 된다.
        hit=""
        case "$(apache_last_directive ServerTokens | cut -f1 | tr 'A-Z' 'a-z')" in prod|productonly) hit=1 ;; esac
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-16: 서버 정보 노출 제한\nServerTokens Prod\nServerSignature Off\n' >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*server_tokens[[:space:]]+off' "$f" 2>/dev/null && hit=1
            # 다른 블록의 server_tokens on/build 도 check 는 노출로 본다 - off 로 바꾼다
            if grep -qE '^[^#]*server_tokens[[:space:]]+(on|build)' "$f" 2>/dev/null; then
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/^([^#]*server_tokens[[:space:]]+)(on|build)/\1off/'
                applied="$applied nginx($f: on->off)"
            fi
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            # server_tokens 는 http/server/location 컨텍스트 전용 - 파일 맨 앞(main)에 넣으면 nginx 기동 실패
            if nginx_http_insert "$conf" "server_tokens off;"; then
                applied="$applied nginx($conf)"
            else
                manual_only="$manual_only nginx($conf 에서 http 블록을 찾지 못함 - http 블록에 'server_tokens off;' 수동 추가)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        f="$tcdir/server.xml"
        if [ -f "$f" ]; then
            hit=$(strip_xml_comments "$f" | grep -nE 'Connector[^>]*server="')
            if [ -z "$hit" ]; then
                fix_backup "$f"
                # check(WEB-16)도 grep 이 "Connector"와 "server=" 가 같은 줄에 있는지로
                # 판정하므로(멀티라인 미지원), 닫는 ">" 를 찾지 않고 "<Connector" 바로 뒤에
                # 삽입한다 - 실제 tomcat:10 기본 server.xml 처럼 속성이 여러 줄에 걸친
                # Connector 에서도 안전하게 동작한다(실기 테스트로 발견한 버그 수정).
                awk '
                    !done && /<Connector[^>]*port="8080"/ { sub(/<Connector/, "<Connector server=\"WebServer\""); done=1 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="응답 헤더의 서버 정보 노출을 제한함:$applied${manual_only:+ / 수동 조치 필요:$manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요:$manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="서버 정보를 노출하는 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}

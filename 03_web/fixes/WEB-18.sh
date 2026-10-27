# WEB-18 (상) 웹 서비스 WebDAV 비활성화 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        # dav 모듈(dav/dav_fs/dav_lock)을 끄면 다른 파일에 남은 Dav/DavLockDB/DavMinTimeout 등이
        # "Invalid command" 가 되어 Apache 가 기동에 실패한다 - 모듈을 끄는 경우 로드되는 모든 설정
        # 파일의 Dav* 지시어도 함께 주석 처리한다(문법 검사는 fix.sh 가 적용 직후 수행).
        dav_loaded=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*LoadModule[[:space:]]+dav(_fs|_lock)?_module' "$f" 2>/dev/null && dav_loaded=1
        done
        for f in $files; do
            [ -f "$f" ] || continue
            if [ -n "$dav_loaded" ]; then
                grep -qE '^[[:space:]]*(LoadModule[[:space:]]+dav(_fs|_lock)?_module|Dav[A-Za-z]*[[:space:]])' "$f" 2>/dev/null || continue
                fix_backup "$f"
                sed -i -E 's/^([[:space:]]*)(LoadModule[[:space:]]+dav(_fs|_lock)?_module.*)/\1#\2/; s/^([[:space:]]*)(Dav[A-Za-z]*[[:space:]].*)/\1#\2/' "$f"
            else
                grep -qE '^[^#]*Dav[[:space:]]+On' "$f" 2>/dev/null || continue
                fix_backup "$f"
                sed -i -E 's/^([[:space:]]*Dav[[:space:]]+)On/\1Off/I' "$f"
            fi
            applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*dav_methods' "$f" 2>/dev/null || continue
            fix_backup "$f"
            sed -i -E 's/^([[:space:]]*)(dav_methods.*)/\1#\2/' "$f"
            applied="$applied nginx($f)"
        done
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="WebDAV 설정을 비활성화함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="WebDAV 가 활성화된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}

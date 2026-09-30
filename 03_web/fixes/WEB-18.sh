# WEB-18 (상) 웹 서비스 WebDAV 비활성화 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*(LoadModule[[:space:]]+dav_module|Dav[[:space:]]+On)' "$f" 2>/dev/null || continue
            fix_backup "$f"
            sed -i -E 's/^([[:space:]]*)(LoadModule[[:space:]]+dav_module.*)/\1#\2/; s/^([[:space:]]*)(LoadModule[[:space:]]+dav_fs_module.*)/\1#\2/; s/^([[:space:]]*Dav[[:space:]]+)On/\1Off/' "$f"
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

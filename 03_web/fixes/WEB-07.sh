# WEB-07 (중) 웹 서비스 경로 내 불필요한 파일 제거 — 조치 [fix: auto]
# checks/WEB-07.sh 와 동일한 대상 경로를 제거한다. 삭제 전 전체 내용을 tar로 백업해
# (fix_backup_remove_path) 원복 시 완전히 복원할 수 있게 한다.
run_fix() {
    detect_web_engines
    removed=""

    case " $WEB_ENGINES " in *" apache "*)
        for p in /usr/local/apache2/htdocs/manual /usr/local/apache2/manual /var/www/manual; do
            [ -e "$p" ] || continue
            fix_backup_remove_path "$p"
            removed="$removed $p"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        for p in /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html; do
            [ -e "$p" ] || continue
            fix_backup_remove_path "$p"
            removed="$removed $p"
        done
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        for p in "$home/webapps/docs" "$home/webapps/examples" "$home/webapps/host-manager" "$home/webapps/ROOT/RELEASE-NOTES.txt"; do
            [ -e "$p" ] || continue
            fix_backup_remove_path "$p"
            removed="$removed $p"
        done
    esac

    if [ -n "$removed" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="기본 샘플/매뉴얼 경로 제거:$removed"
        FIX_EVIDENCE="$removed"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="제거 대상 경로가 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}

# U-32 (중) 홈 디렉토리로 지정한 디렉토리의 존재 관리 — 조치
# 가이드 조치 방법: 홈 디렉토리가 존재하지 않으면 생성
run_fix() {
    passwd_file="/etc/passwd"
    applied=""
    while IFS=: read -r name _ _ _ _ home shell; do
        [ -z "$name" ] && continue
        case "$home" in
            /|/nonexistent|/nonexisting|"") continue ;;
        esac
        case "$shell" in
            */nologin|/bin/false) continue ;;
        esac
        [ -d "$home" ] && continue
        # 새로 만들 디렉터리이므로 원복 시 삭제되도록 먼저 WAS_ABSENT 마커를 남긴다
        fix_backup "$home"
        mkdir -p "$home" 2>/dev/null
        chown "$name" "$home" 2>/dev/null
        chmod 750 "$home" 2>/dev/null
        applied="$applied $home($name)"
    done < "$passwd_file"

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="홈 디렉토리가 없는 계정이 없어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="홈 디렉토리를 새로 생성함(750, 계정 소유):$applied"; FIX_EVIDENCE="$applied"
    fi
}

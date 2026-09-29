# U-09 (하) 계정이 존재하지 않는 GID 금지 — 조치
# 가이드 조치 방법: /etc/group 과 /etc/passwd 를 비교해 고아 GID 정리
# 자동화 범위: 계정을 다른 그룹으로 옮기는 것은 업무 영향을 알 수 없어 위험하므로, 고아 GID에
# 해당하는 그룹을 /etc/group 에 새로 만들어(gid<번호>) "존재하지 않는 GID" 상태만 해소한다.
run_fix() {
    passwd_file="/etc/passwd"; group_file="/etc/group"
    group_gids=$(awk -F: '{print $3}' "$group_file" | sort -un)
    orphan_gids=$(awk -F: '{print $4}' "$passwd_file" | sort -un | while IFS= read -r gid; do
        printf '%s\n' "$group_gids" | grep -qx "$gid" || echo "$gid"
    done)

    if [ -z "$orphan_gids" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="고아 GID가 이미 없음(조치 불필요)"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$group_file"
    applied=""
    for gid in $orphan_gids; do
        if groupadd -g "$gid" "gid${gid}" 2>/dev/null; then
            applied="$applied gid${gid}(${gid})"
        fi
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="FAILED"; FIX_DETAIL="groupadd 실행 실패 (대상 GID: $orphan_gids)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="고아 GID에 대응하는 그룹을 생성함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

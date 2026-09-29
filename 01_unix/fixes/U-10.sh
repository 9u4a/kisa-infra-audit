# U-10 (중) 동일한 UID 금지 — 조치
# 가이드 조치 방법: 중복 UID 계정을 개별 UID로 재할당
# 자동화 범위: 계정 삭제는 하지 않고, 중복된 각 UID 그룹에서 첫 번째를 제외한 나머지 계정을
# 미사용 UID로 재할당한다(usermod -u).
run_fix() {
    passwd_file="/etc/passwd"
    dup_uids=$(awk -F: '{print $3}' "$passwd_file" | sort -n | uniq -d)
    if [ -z "$dup_uids" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="중복 UID가 이미 없음(조치 불필요)"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$passwd_file"
    [ -f /etc/shadow ] && fix_backup /etc/shadow

    newuid=$(awk -F: '{print $3}' "$passwd_file" | sort -n | tail -1)
    newuid=$((newuid + 1))
    applied=""
    for uid in $dup_uids; do
        accounts=$(awk -F: -v u="$uid" '$3 == u {print $1}' "$passwd_file")
        _first=1
        for acct in $accounts; do
            if [ "$_first" -eq 1 ]; then
                _first=0
                continue
            fi
            if usermod -u "$newuid" "$acct" 2>/dev/null; then
                applied="$applied ${acct}->uid=${newuid}"
                newuid=$((newuid + 1))
            fi
        done
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="FAILED"; FIX_DETAIL="usermod 실행 실패 (중복 UID: $dup_uids)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="중복 UID 계정을 재할당함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

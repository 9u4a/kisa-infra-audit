# U-05 (상) root 이외의 UID가 '0' 금지 — 조치
# 가이드 조치 방법: root 외 UID 0 계정의 UID 를 다른 값으로 변경(또는 삭제)
# 자동화 범위: 삭제는 데이터 손실 위험이 있어 하지 않고, 미사용 UID로 재할당한다(usermod -u).
run_fix() {
    passwd_file="/etc/passwd"
    extra=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' "$passwd_file")
    if [ -z "$extra" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="root 외 UID 0 계정이 이미 없음(조치 불필요)"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$passwd_file"
    [ -f /etc/shadow ] && fix_backup /etc/shadow

    newuid=$(awk -F: '{print $3}' "$passwd_file" | sort -n | tail -1)
    newuid=$((newuid + 1))
    applied=""
    for acct in $extra; do
        if usermod -u "$newuid" "$acct" 2>/dev/null; then
            applied="$applied ${acct}->uid=${newuid}"
            newuid=$((newuid + 1))
        fi
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="FAILED"; FIX_DETAIL="usermod 실행 실패 (대상: $extra)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="root 외 UID 0 계정의 UID 를 재할당함:$applied"; FIX_EVIDENCE="$applied"
    fi
}

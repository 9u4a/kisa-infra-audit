# U-26 (상) /dev에 존재하지 않는 device 파일 점검 — 조치
# 가이드 조치 방법: major/minor 번호가 없는(위장) device 파일 제거
run_fix() {
    fake=$(find /dev -xdev -type f -not -path '/dev/mqueue/*' -not -path '/dev/shm/*' 2>/dev/null | head -n 50)
    if [ -z "$fake" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="제거 대상 위장 device 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    printf '%s\n' "$fake" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        fix_backup "$f"
        rm -f "$f"
    done
    FIX_STATUS="APPLIED"
    FIX_DETAIL="/dev 내 major/minor 번호가 없는 일반 파일을 제거함"
    FIX_EVIDENCE="$fake"
}

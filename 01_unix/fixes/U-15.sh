# U-15 (상) 파일 및 디렉터리 소유자 설정 — 조치
# 가이드 조치 방법: 소유자가 존재하지 않는 파일/디렉터리의 소유자를 지정(가이드는 관리자가
# 검토 후 적절한 소유자로 지정할 것을 권고 — 자동화 범위: 어떤 계정이 적절한지 알 수 없으므로
# 안전한 기본값인 root:root 로 설정하고, 개별 검토가 필요함을 명시한다).
run_fix() {
    if ! command -v find >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="find 명령을 사용할 수 없음"; FIX_EVIDENCE=""
        return
    fi
    _list=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | head -n 200)
    if [ -z "$_list" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="소유자/그룹 없는 파일이 이미 없음(조치 불필요)"; FIX_EVIDENCE=""
        return
    fi
    _n=0
    printf '%s\n' "$_list" | while IFS= read -r _f; do
        [ -z "$_f" ] && continue
        fix_backup "$_f"
        chown root:root "$_f" 2>/dev/null
    done
    _n=$(printf '%s\n' "$_list" | grep -c .)
    FIX_STATUS="APPLIED"
    FIX_DETAIL="소유자/그룹이 없는 파일 최대 200건을 root:root 로 설정함(임시 조치 — 실제 적절한 소유자로 재검토 권장)"
    FIX_EVIDENCE="처리 건수: $_n"
}

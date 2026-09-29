# U-40 (상) NFS 접근 통제 — 조치
run_fix() {
    exports="/etc/exports"
    if [ ! -s "$exports" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="NFS 미사용($exports 없음/비어있음)으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$exports"
    chmod 644 "$exports" 2>/dev/null
    # 전체 공개(*) 공유는 자동으로 특정 IP로 바꿀 수 없으므로 위험을 줄이기 위해 주석 처리한다.
    sed -i -E '/^[[:space:]]*[^#].*(^|[[:space:]])\*(\(|[[:space:]])/ s/^/#/' "$exports"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$exports 권한을 644로 설정하고 전체 공개(*) 공유 라인을 주석 처리함(허용할 IP를 지정해 다시 활성화 필요)"
    FIX_EVIDENCE="$(grep -vE '^[[:space:]]*#' "$exports")"
}

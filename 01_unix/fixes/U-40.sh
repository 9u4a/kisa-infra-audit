# U-40 (상) NFS 접근 통제 — 조치
# check(U-40)와 같은 범위·기준(진단 검수 U-R15): /etc/exports + /etc/exports.d/*.exports, "*" 또는 호스트를 생략한
# 전체 공개 공유 줄.
run_fix() {
    files=""
    for f in /etc/exports /etc/exports.d/*.exports; do
        [ -s "$f" ] && files="$files $f"
    done
    if [ -z "$files" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="NFS 미사용(/etc/exports·exports.d 없음/비어있음)으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    evd=""
    for f in $files; do
        fix_backup "$f"
        chmod 644 "$f" 2>/dev/null
        # 전체 공개 공유는 자동으로 특정 IP로 바꿀 수 없으므로 위험을 줄이기 위해 주석 처리한다.
        _tmp="$f.kisa.$$"
        awk '/^[[:space:]]*(#|$)/ { print; next }
             NF == 1 { print "#" $0; next }
             { o = 0; for (i = 2; i <= NF; i++) if ($i ~ /^\(/ || $i ~ /^\*(\(|$)/) o = 1; print (o ? "#" : "") $0 }' "$f" > "$_tmp" \
            && cat "$_tmp" > "$f"
        rm -f "$_tmp"
        evd="$evd
$f: $(grep -vE '^[[:space:]]*#' "$f")"
    done
    # 파일만 고치면 커널의 공유 목록은 그대로라 실제로는 열린 채 재진단만 GOOD 이었다(실무 적용 검증 P-15) - 즉시 반영한다.
    # 원복(--rollback)은 파일만 되돌리므로 공유를 다시 열려면 exportfs -ra 를 직접 실행해야 한다(F4 고지).
    if command -v exportfs >/dev/null 2>&1; then
        if run_to 30 exportfs -ra >/dev/null 2>&1; then reload="exportfs -ra 로 즉시 반영함"
        else reload="exportfs -ra 실패 - 공유 목록에 아직 반영되지 않았을 수 있음(직접 확인)"; fi
    else
        reload="exportfs 명령 없음 - NFS 서버 재시작 전까지 반영되지 않음"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NFS 설정 파일(${files# }) 권한을 644로 설정하고 전체 공개(* 또는 호스트 생략) 공유 라인을 주석 처리함(허용할 IP를 지정해 다시 활성화 필요). $reload. 원복 시 파일만 되돌리므로 exportfs -ra 를 다시 실행할 것"
    FIX_EVIDENCE="$evd"
}

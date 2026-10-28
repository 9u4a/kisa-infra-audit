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
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NFS 설정 파일(${files# }) 권한을 644로 설정하고 전체 공개(* 또는 호스트 생략) 공유 라인을 주석 처리함(허용할 IP를 지정해 다시 활성화 필요)"
    FIX_EVIDENCE="$evd"
}

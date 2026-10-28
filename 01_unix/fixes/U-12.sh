# U-12 (하) 세션 종료 시간 설정 — 조치
# 가이드 조치 방법: TMOUT 을 600초(10분) 이하로 설정
run_fix() {
    f="/etc/profile"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$f"
    # check(U-12)와 같이 따옴표·readonly 등이 붙은 형태도 대상으로 한다(진단 검수 U-R7). TMOUT=0 도 600 으로 바뀐다.
    if grep -qE '^[[:space:]]*((export|readonly|typeset|declare)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+)?TMOUT=["'"'"']?[0-9]+' "$f"; then
        sed -i -E 's/^[[:space:]]*((export|readonly|typeset|declare)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+)?TMOUT=["'"'"']?[0-9]+.*/TMOUT=600/' "$f"
    else
        printf 'TMOUT=600\n' >> "$f"
    fi
    grep -qE '^[[:space:]]*export[[:space:]]+TMOUT([[:space:]]|$)' "$f" || printf 'export TMOUT\n' >> "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$f 에 TMOUT=600(10분) 설정 및 export 처리함"
    FIX_EVIDENCE="$(grep TMOUT "$f")"
}

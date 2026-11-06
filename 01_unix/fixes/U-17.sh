# U-17 (상) 시스템 시작 스크립트 권한 설정 — 조치
# 변경: systemd 유닛(/etc/systemd/system 깊이 2)과 init 시작 스크립트(/etc/init.d, /etc/rc.d 깊이 2, /etc/rc.local) 중
#       비 root 소유·그룹/기타 쓰기 가능 파일(최대 50건, 심볼릭 링크는 대상 파일)을 소유자 root, chmod go-w
# 가이드 조치 방법: 시작 스크립트를 root 소유로, 일반 사용자 쓰기 권한 제거. check(U-17)와 같은 대상(1.5.0 A4 - 예전에는
# systemd 폴더만, 그것이 없으면 레거시 init 은 미조치 ERROR).
run_fix() {
    _targets=""
    for _t in /etc/systemd/system /etc/init.d /etc/rc.d /etc/rc.local; do
        [ -e "$_t" ] && _targets="$_targets $_t"
    done
    if [ -z "$_targets" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="시스템 시작 스크립트 디렉터리를 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    # -perm -0022 는 "그룹과 기타 모두 쓰기"일 때만 맞아 0664/0646 이 통과했다(진단 검수 U-R2) - 둘 중 하나라도 쓰기면 위반.
    # find -L 결과는 링크 경로(/etc/rc.d/rc3.d/S..)일 수 있다 - 링크 경로로 백업·원복하면 원복이 링크를 일반 파일로
    # 바꾸므로 실제 파일 경로(readlink -f)로 바꿔 중복을 없앤 뒤 조치한다.
    _list=$(for _t in $_targets; do
                find -L "$_t" -maxdepth 2 -type f \( ! -user root -o -perm -0020 -o -perm -0002 \) 2>/dev/null
            done | while IFS= read -r _p; do readlink -f "$_p" 2>/dev/null || printf '%s\n' "$_p"; done | sort -u | head -n 50)
    if [ -z "$_list" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 시작 스크립트가 없음"; FIX_EVIDENCE=""
        return
    fi
    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
    while IFS= read -r _f; do
        [ -z "$_f" ] && continue
        fix_backup "$_f"
        chown root "$_f" 2>/dev/null
        chmod go-w "$_f" 2>/dev/null
    done <<EOF
$_list
EOF
    FIX_STATUS="APPLIED"
    FIX_DETAIL="시스템 시작 스크립트를 root 소유로, 그룹/기타 쓰기 권한을 제거함"
    FIX_EVIDENCE="$_list"
}

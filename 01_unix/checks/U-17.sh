# U-17 (상) 시스템 시작 스크립트 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root, 일반 사용자 쓰기 권한 없음 / 취약 = 그 외
# 자동화 범위: systemd 유닛(/etc/systemd/system, 깊이 2)과 init 시작 스크립트(/etc/init.d, /etc/rc.d 아래 깊이 2,
#             /etc/rc.local)를 함께 판정한다(심볼릭 링크는 대상 파일 기준 - 가이드 readlink -f 와 같음).
# 1.5.0 A4: 예전에는 /etc/systemd/system 이 있으면 거기서 끝내 /etc/init.d 의 rc 스크립트를 보지 않았다(systemd 도
#           sysv-generator 로 init.d 스크립트를 실행한다). 레거시만 있는 시스템은 MANUAL 이었다.

# u17_targets -- 판정 대상 폴더/파일 중 존재하는 것(한 줄에 하나)
u17_targets() {
    for _t in /etc/systemd/system /etc/init.d /etc/rc.d /etc/rc.local; do
        [ -e "$_t" ] && printf '%s\n' "$_t"
    done
}

# u17_violations -- 비 root 소유이거나 그룹/기타 쓰기가 있는 시작 스크립트(최대 50건, fix 와 공용 기준)
# -perm -0022 는 "그룹과 기타 모두 쓰기"일 때만 맞아 0664/0646 이 통과했다(진단 검수 U-R2) - 둘 중 하나라도 쓰기면 위반.
u17_violations() {
    u17_targets | while IFS= read -r _t; do
        find -L "$_t" -maxdepth 2 -type f \( ! -user root -o -perm -0020 -o -perm -0002 \) 2>/dev/null
    done | sort -u | head -n 50
}

run_check() {
    targets=$(u17_targets | tr '\n' ' ')
    if [ -z "$targets" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="시스템 시작 스크립트 디렉터리를 찾을 수 없음"
        CHECK_EVIDENCE=""
        return
    fi
    violations=$(u17_violations)
    if [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="시스템 시작 스크립트(${targets% })가 root 소유이며 그룹/기타 쓰기 권한이 없음"
        CHECK_EVIDENCE="검사 대상: $targets"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="root 소유가 아니거나 그룹/기타 쓰기 권한이 부여된 시스템 시작 스크립트가 존재함 (최대 50건)"
        CHECK_EVIDENCE="$violations"
    fi
}

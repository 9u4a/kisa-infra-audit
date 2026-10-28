# U-30 (중) UMASK 설정 관리
# 판단 기준(가이드 원문): 양호 = UMASK 값이 022 이상으로 설정된 경우
#                        취약 = 022 미만으로 설정된 경우
# 전 Unix 계열 공통 로직: /etc/profile, /etc/login.defs(Linux) 확인.

# 진단 검수 U-R15: 예전에는 /etc/profile → /etc/login.defs 순으로 읽어 login.defs 값이 최종값이 됐지만, 실제로는
# 로그인 시 login.defs(pam_umask/login) 가 먼저 적용되고 그 뒤 셸이 /etc/profile → /etc/profile.d/*.sh →
# /etc/bashrc(/etc/bash.bashrc) 를 실행하며 덮어쓴다. 이 순서대로 읽고 마지막 값을 최종값으로 본다(주석 줄 제외).
# 한계: if 분기 안의 umask(RHEL /etc/bashrc 의 UID>199 → 002 등)는 조건을 평가하지 않고 마지막 줄을 쓴다.
# "022 이상" 은 그룹·기타 쓰기 비트(022)가 모두 마스킹되는지로 본다(예전 10진 비교는 umask 100 등을 GOOD 으로 봄).
run_check() {
    evidence=""
    val=""

    for f in /etc/login.defs /etc/profile /etc/profile.d/*.sh /etc/bashrc /etc/bash.bashrc; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f" 2>/dev/null | tail -n1)
        [ -z "$line" ] && continue
        evidence="$evidence
$f: $line"
        val=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[Uu][Mm][Aa][Ss][Kk][[:space:]]+([0-7]+).*/\1/')
    done

    if [ -z "$val" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="/etc/login.defs, /etc/profile(.d), /etc/bashrc 에서 UMASK 설정을 찾지 못함 (기본값 또는 다른 파일에서 설정되었을 수 있음)"
        CHECK_EVIDENCE=""
        return
    fi

    if [ $(( 0$val & 022 )) -eq $(( 022 )) ] 2>/dev/null; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="최종 UMASK=${val} (022 이상)으로 설정됨"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="최종 UMASK=${val} 로 022 미만(그룹/기타 쓰기 허용)으로 설정됨"
    fi
    CHECK_EVIDENCE=$(printf '%s' "$evidence" | sed '/^$/d')
}

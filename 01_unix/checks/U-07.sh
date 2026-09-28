# U-07 (하) 불필요한 계정 제거
# 판단 기준(가이드 원문): 양호 = 불필요한 계정이 존재하지 않는 경우 / 취약 = 존재하는 경우
# "불필요"는 조직의 인사·운영 맥락(퇴직/휴직 등)에 달려 있어 완전 자동 판정이 불가능하다.
# 자동화 범위: 로그인 가능한(shell 이 nologin/false 가 아닌) 계정 목록과 최근 로그인 이력을
#             근거로 제시하고, 최종 판단은 관리자가 하도록 MANUAL 로 응답한다.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    loginable=$(awk -F: '$7 !~ /(nologin|false)$/ {print $1":"$3":"$7}' "$passwd_file")
    last_info=""
    if command -v last >/dev/null 2>&1; then
        last_info=$(last -n 20 2>/dev/null | grep -v '^$' | head -n 20)
    fi

    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="계정의 '불필요' 여부는 조직 운영 정보(퇴직/휴직 등)가 필요해 자동 판정할 수 없음. 아래 로그인 가능 계정 목록과 최근 로그인 이력을 근거로 수동 검토 필요"
    CHECK_EVIDENCE="[로그인 가능(shell != nologin/false) 계정: name:uid:shell]
${loginable:-없음}

[최근 로그인 이력(last, 최대 20건)]
${last_info:-확인 불가}"
}

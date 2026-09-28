# U-14 (상) root 홈, 패스 디렉터리 권한 및 패스 설정
# 판단 기준(가이드 원문): 양호 = PATH 환경변수에 "." 이 맨 앞이나 중간에 포함되지 않은 경우
#                        취약 = 맨 앞이나 중간에 포함된 경우 (맨 뒤는 조치방법상 허용)
# 전 Unix 계열 공통 로직: 현재 실행 PATH + root 쉘 시작 파일들을 검사.

run_check() {
    evidence="실행 환경 PATH=$PATH"
    violation=0

    check_one_path() {
        _p=$1
        _old_ifs=$IFS; IFS=:
        set -- $_p
        IFS=$_old_ifs
        _n=$#
        _i=0
        for _entry in "$@"; do
            _i=$((_i + 1))
            if { [ "$_entry" = "." ] || [ -z "$_entry" ]; } && [ "$_i" -lt "$_n" ]; then
                violation=1
            fi
        done
    }

    check_one_path "$PATH"

    for f in /root/.bash_profile /root/.bashrc /root/.profile /etc/profile; do
        [ -f "$f" ] || continue
        line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?PATH=' "$f" 2>/dev/null | tail -n1)
        [ -z "$line" ] && continue
        evidence="$evidence
$f: $line"
        val=$(printf '%s' "$line" | sed -E 's/^[^=]*=//')
        check_one_path "$val"
    done

    if [ "$violation" -eq 1 ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="PATH 환경변수의 맨 앞 또는 중간에 현재 디렉터리(\".\")가 포함되어 있음"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="PATH 환경변수의 맨 앞/중간에 현재 디렉터리(\".\")가 포함되어 있지 않음"
    fi
    CHECK_EVIDENCE="$evidence"
}

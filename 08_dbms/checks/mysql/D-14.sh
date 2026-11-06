# D-14 (중) 데이터베이스의 주요 설정 파일, 비밀번호 파일 등의 접근 권한 적절성 [MySQL]
# 가이드 원문 "대상"에는 Oracle DB/PostgreSQL/Cubrid만 명시되어 있으나, 같은 항목의
# "점검 및 조치 사례" 본문에는 MySQL my.cnf 파일 권한(600/640) 절차가 그대로 포함되어 있다.
# 이는 가이드 자체의 대상 표기 누락으로 보고(deviation), 조치 방법이 실존하는 MySQL 설정 파일에도
# 동일하게 적용한다. 판단 기준: 양호 = 일반 사용자의 수정 권한 제거(권한 <= 640) / 취약 = 아님.
# 외부 검수 A17: 고정 경로 첫 파일 하나만 보던 것을 서버가 실제로 읽는 설정 파일 전부(--defaults-file, !include/!includedir)와
# debian.cnf(비밀번호 파일)로 넓혔다(lib/common_db.sh mysql_config_files). 하나라도 위반이면 취약.
run_check() {
    db_remote_skip "my.cnf 파일 권한" && return
    files=$(mysql_config_files)
    if [ -z "$files" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    _bad=""; _unk=""; _ok=""; _evidence=""
    old_ifs=$IFS; IFS='
'
    for f in $files; do
        IFS=$old_ifs
        check_owner_perm "$f" "root mysql" 640
        _evidence="$_evidence
[$f] $CHECK_STATUS $CHECK_DETAIL
$CHECK_EVIDENCE"
        case "$CHECK_STATUS" in
            VULN) _bad="$_bad $f" ;;
            GOOD) _ok="$_ok $f" ;;
            *) _unk="$_unk $f" ;;
        esac
        IFS='
'
    done
    IFS=$old_ifs
    CHECK_EVIDENCE="$_evidence"
    if [ -n "$_bad" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="다음 설정/비밀번호 파일의 소유자·권한이 부적절함:$_bad${_unk:+ / 확인 못 함:$_unk}"
    elif [ -n "$_unk" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="다음 파일의 권한을 확인하지 못함:$_unk"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="서버가 읽는 설정 파일과 비밀번호 파일의 소유자·권한이 적절함:$_ok"
    fi
}

# lib/common_fix.sh — 자동 조치(fix) 공통: 백업·원복·감사 로그, 설정 파일 편집(F2), 비밀번호 직접 입력,
#   fix 진입점 가드(F1·F6), 서비스·권한 조치, 전체 원복
# lib/common.sh 가 source 한다(직접 source 하지 말 것). 1.5.0 D3 에서 common.sh(2686줄)를 나눴다 - 함수는 모두
# common.sh 를 source 한 뒤 쓸 수 있고, 최상위 코드는 변수 할당뿐이라 파일 순서와 무관하다.
# shellcheck shell=sh

# ============================================================================
# ---- 자동 조치(fix) 공통 -------------------
# ============================================================================
# 진단(run.*)과 완전히 분리된 fix.* 전용 헬퍼. run.* 는 절대 이 함수들을 쓰지 않는다.

# result.json(진단 결과)에서 status=VULN 인 코드 목록만 추출한다. result_add() 가 만드는
# 포맷은 guide.json 과 달리 항목당 한 줄에 compact JSON(들여쓰기 없음)으로 저장되므로
# guide_field() 와는 다른 파서가 필요하다.
result_list_vuln_codes() {
    _json=$1
    grep '"status":"VULN"' "$_json" | grep -o '"code":"[A-Z]*-[0-9]*"' | sed -E 's/.*"([A-Z]+-[0-9]+)".*/\1/'
}

# _rt_field <result.json> <키> -- result_finalize 가 쓰는 머리 부분("키": "값")의 값. items 안의 문자열은
# json_escape 로 따옴표가 \" 가 되어 이 패턴에 걸리지 않는다.
_rt_field() {
    grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null | head -n 1 | sed 's/^[^:]*:[[:space:]]*"\(.*\)"$/\1/'
}

# _rt_days <YYYY-MM-DD> -- 날짜를 일 수로(그레고리력, 차이 계산용). date -d 는 GNU 전용이라 쓰지 않는다.
_rt_days() {
    printf '%s\n' "$1" | awk -F- '{ y = $1 + 0; m = $2 + 0; d = $3 + 0; if (m <= 2) { y--; m += 12 }
        print 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d }'
}

# fix_check_result_target <result.json> <run.sh 의 카테고리 이름> [엔진] -- X-06(1.3.4): 조치 입력 result.json 이
# 이 호스트·이 카테고리(·08 은 이 엔진)의 진단 결과인지 확인한다. 예전에는 result_list_vuln_codes 가 아무 결과나
# 받아, 다른 서버(또는 오래된) 결과로 --apply --yes 를 돌리면 auto 항목이 확인 없이 바뀌었다(원복에만 호스트 확인이
# 있었음). Windows 쪽 Test-FixResultTarget 과 같은 기준:
#   호스트·카테고리·엔진 불일치 → --force(FORCE=1) 없이는 변경 없이 exit 2 (dry-run 도 같음 - 남의 결과 미리보기는 무의미)
#   진단 시각(generated_at)이 7일 넘게 지났거나 해석 불가 → --apply 면 터미널에서 y 확인(--force 면 경고만, --yes 로는
#   넘어가지 않음 - 그 사이 설정이 바뀌었을 수 있어서), 비대화형이면 변경 없이 exit 2. dry-run 은 경고만.
fix_check_result_target() {
    _rt_json=$1; _rt_cat=$2; _rt_env=${3:-}
    _rt_this=$(host_name)
    _rt_h=$(_rt_field "$_rt_json" host)
    _rt_c=$(_rt_field "$_rt_json" category)
    _rt_e=$(_rt_field "$_rt_json" env)
    _rt_bad=""
    [ "$_rt_h" = "$_rt_this" ] || _rt_bad="$_rt_bad / 호스트 불일치(결과: ${_rt_h:-없음}, 현재: $_rt_this)"
    [ "$_rt_c" = "$_rt_cat" ] || _rt_bad="$_rt_bad / 카테고리 불일치(결과: ${_rt_c:-없음}, 기대: $_rt_cat)"
    if [ -n "$_rt_env" ] && [ "$_rt_e" != "$_rt_env" ]; then
        _rt_bad="$_rt_bad / 엔진 불일치(결과: ${_rt_e:-없음}, 지정: $_rt_env)"
    fi
    if [ -n "$_rt_bad" ]; then
        _rt_bad=${_rt_bad# / }
        if [ "${FORCE:-0}" -eq 1 ]; then
            log_warn "--force 로 계속합니다: $_rt_bad"
        else
            log_error "이 result.json 은 이 대상의 진단 결과가 아닙니다 - $_rt_bad. 변경 없이 중단합니다(의도한 경우 --force): $_rt_json"
            exit 2
        fi
    fi
    _rt_gen=$(_rt_field "$_rt_json" generated_at)
    _rt_d=$(printf '%s' "$_rt_gen" | sed -n 's/^\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)T.*/\1/p')
    _rt_old=""
    if [ -z "$_rt_d" ]; then
        _rt_old="진단 시각(generated_at)을 해석할 수 없음: ${_rt_gen:-없음}"
    else
        _rt_age=$(( $(_rt_days "$(date '+%Y-%m-%d')") - $(_rt_days "$_rt_d") ))
        [ "$_rt_age" -gt 7 ] && _rt_old="진단 결과가 ${_rt_age}일 전 것임($_rt_gen) - 그 사이 설정이 바뀌었을 수 있음"
    fi
    [ -n "$_rt_old" ] || return 0
    if [ "${FORCE:-0}" -eq 1 ]; then
        log_warn "--force 로 계속합니다: $_rt_old"
    elif [ "${APPLY:-0}" -ne 1 ]; then
        log_warn "$_rt_old (dry-run 이라 계속 - --apply 때는 확인을 받음, 가능하면 진단을 다시 실행할 것)"
    else
        log_warn "$_rt_old"
        if ! fix_confirm_tty "그래도 이 진단 결과로 조치를 진행하시겠습니까?"; then
            log_error "중단 - 아무것도 변경하지 않았습니다. 진단(run.sh)을 다시 실행하세요(비대화형에서 그대로 진행하려면 --force)."
            exit 2
        fi
    fi
    return 0
}

# fix_prepare_dir <base_dir> <category_num> -> FIX_OUT_DIR/FIX_BACKUP_DIR/FIX_LOG 설정
fix_prepare_dir() {
    _base=$1; _cat_num=$2
    _host=$(host_name)
    _ts=$(date '+%Y%m%d-%H%M%S')
    FIX_OUT_DIR="${_base}/${_host}_${_cat_num}_fix_${_ts}-$$"
    FIX_BACKUP_DIR="$FIX_OUT_DIR/backup"
    make_private_dir "$FIX_OUT_DIR"
    make_private_dir "$FIX_BACKUP_DIR"
    FIX_LOG="$FIX_OUT_DIR/changes.log"
    # 감사 로그(운영 안전 기준 F6): 누가 언제 어느 호스트에서 바꿨는지 첫 줄에 남기고, 각 줄 앞에는
    # fix_log_stamp 가 시각을 붙인다(형식: 시각<TAB>코드<TAB>등급<TAB>결과<TAB>상세).
    # 1.6.0 G-03: 정책 모드면 그 앞(맨 앞)에 감사 기록(키=값 줄, audit.txt 와 같은 내용)을 둔다.
    : > "$FIX_LOG"
    fix_audit_begin
    printf '# 조치 실행 시작 %s / 호스트 %s / 실행자 %s(uid=%s, sudo=%s) / 도구 v%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')" "$_host" "$(id -un 2>/dev/null)" "$(id -u 2>/dev/null)" "${SUDO_USER:-없음}" "$TOOL_VERSION" >> "$FIX_LOG"
}

# fix_log_stamp — 표준입력의 각 줄 앞에 시각을 붙인다(changes.log 기록용)
fix_log_stamp() {
    while IFS= read -r _ls; do printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_ls"; done
}

# fix_abort_item <사유> — 백업 실패처럼 "이대로 바꾸면 원복할 수 없는" 상황(운영 안전 기준 F1).
# 이 항목에서 이미 백업·변경한 것을 원복하고 조치 실행 전체를 중단한다(이후 항목도 바꾸지 않음).
# X-04(1.3.4) 종료 코드 규약: exit 3 은 이 함수 전용이다. 조치는 run_fix_isolated 의 서브셸에서 돌고, 그
# 서브셸이 3 으로 끝나면 fix.sh 가 이어서 exit 3 으로 실행 전체를 끝낸다(예전 동작과 같음). 조치 안에서
# 다시 파이프(| while)·$(...) 같은 "한 단계 더 안쪽" 서브셸에서 fix_backup 을 부르면 그 exit 3 은 그 안쪽만
# 끝내고 조치는 계속 진행되므로 여전히 금지다(here-doc 반복문을 쓸 것).
fix_abort_item() {
    log_error "[${FIX_CODE:-?}] $1 — 이 항목의 변경을 원복하고 조치 실행을 중단합니다(이후 항목은 변경하지 않음)."
    [ -n "${FIX_CODE:-}" ] && fix_rollback_item "$FIX_CODE"
    printf '%s\t-\tABORTED\t%s (이 항목 원복 후 실행 중단)%s\n' "${FIX_CODE:-?}" "$1" \
        "$(printf '%s' "${FIX_ROLLBACK_FAILS:-}" | tr '\n' ' ')" | fix_log_stamp >> "${FIX_LOG:-/dev/null}"
    exit 3
}

# run_fix_isolated <fix 파일> -- X-04(1.3.4): 조치 1개를 서브셸에서 실행하고 FIX_STATUS/FIX_DETAIL/FIX_EVIDENCE 를
# 받아온다. 예전에는 fix.sh 가 조치 파일을 현재 셸에서 실행해(. "$fix_file"; run_fix), set -u 의 미설정 변수 하나나
# 치명 오류로 fix.sh 전체가 죽었다 - 그 항목은 반쯤 바뀐 채 원복도 changes.log 기록도 없이 남고 이후 항목도
# 처리되지 않았다. 진단 쪽 run_check_isolated(R-01)와 같은 방식이다. 반환값 규약:
#   0    조치가 끝까지 실행되어 결과를 남김 - 성공/실패 판정·재검증·원복은 기존대로 fix.sh 가 한다
#   3    fix_abort_item(백업 실패 등, F1): 서브셸 안에서 이미 이 항목을 원복하고 ABORTED 를 기록했다 -
#        호출부(fix.sh)는 exit 3 으로 실행 전체를 끝낸다(이후 항목은 바꾸지 않음)
#   1    비정상 종료(미설정 변수·문법 오류·예상 밖 exit 등): FIX_STATUS=ERROR + 사유(종료 코드·표준오류 끝부분).
#        fix.sh 의 실패 경로가 fix_rollback_item 으로 이 항목에서 백업한 것을 되돌리고 FAILED_ROLLED_BACK /
#        FAILED_NOT_ROLLED_BACK 을 기록한 뒤 다음 항목으로 넘어간다
# fix.sh 가 조치 뒤에 쓰는 전역 값은 FIX_STATUS/DETAIL/EVIDENCE 뿐이다(백업·원복 기록은 FIX_BACKUP_DIR 의 파일,
# changes.log 는 파일로 남으므로 그대로 전달됨). 조치 안에서 바꾼 IFS 등 다른 전역 값은 다음 항목으로 새지 않는다.
# 서브셸은 표준입출력과 /dev/tty 를 그대로 물려받아 확인(fix_confirm_tty)·비밀번호 입력(fix_read_new_password,
# stty -echo)이 그대로 동작한다. 표준오류는 사유를 남기려고 파일로 받아 항목이 끝난 뒤 한꺼번에 보여 준다.
run_fix_isolated() {
    _rfi_dir="${FIX_OUT_DIR:-${TMPDIR:-/tmp}}/.fix.$$"
    rm -rf "$_rfi_dir"
    # 결과를 받을 곳조차 만들 수 없으면(디스크 가득 참 등 - 백업도 실패할 상황) 조치하지 않고 중단한다(F1)
    ( umask 077; mkdir -p "$_rfi_dir" ) 2>/dev/null \
        || fix_abort_item "조치 결과 임시 폴더를 만들 수 없음(디스크 공간·권한 확인): $_rfi_dir"
    (
        trap - EXIT
        FIX_STATUS="ERROR"; FIX_DETAIL="조치 스크립트가 결과를 반환하지 않음"; FIX_EVIDENCE=""
        # shellcheck disable=SC1090
        . "$1"
        if command -v run_fix >/dev/null 2>&1; then run_fix; fi
        printf '%s' "$FIX_STATUS" > "$_rfi_dir/s" && printf '%s' "$FIX_DETAIL" > "$_rfi_dir/d" \
            && printf '%s' "$FIX_EVIDENCE" > "$_rfi_dir/e" && : > "$_rfi_dir/ok"
    ) 2> "$_rfi_dir/err"
    _rfi_rc=$?
    [ -s "$_rfi_dir/err" ] && cat "$_rfi_dir/err" >&2
    if [ "$_rfi_rc" -eq 3 ]; then
        rm -rf "$_rfi_dir"
        return 3
    fi
    if [ -f "$_rfi_dir/ok" ]; then
        FIX_STATUS=$(cat "$_rfi_dir/s"); FIX_DETAIL=$(cat "$_rfi_dir/d"); FIX_EVIDENCE=$(cat "$_rfi_dir/e")
        _rfi_rc=0
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="조치 스크립트 비정상 종료(rc=$_rfi_rc, 변경 도중 멈췄을 수 있음): $(tail -n 2 "$_rfi_dir/err" 2>/dev/null | tr '\n' ' ')"
        FIX_EVIDENCE=""
        _rfi_rc=1
    fi
    rm -rf "$_rfi_dir"
    return "$_rfi_rc"
}

# fix_backup <파일경로> — 항목별(FIX_CODE) 백업 디렉터리에 원본을 상대경로 구조로 보존한다.
# 파일이 원래 존재하지 않았으면(조치가 "새로 생성"인 경우) .WAS_ABSENT 마커만 남겨
# 원복 시 삭제해야 함을 표시한다. fixes/<코드>.sh 는 파일을 고치기 전에 반드시 이 함수를 부른다.
# - 백업에 실패하면 변경하지 않고 중단한다(fix_abort_item). 예전에는 cp 실패를 무시하고 조치를
#   진행해, 디스크가 가득 찬 상황에서 잘린 백업으로 원복 시 원본을 덮어쓸 수 있었다.
# - 같은 항목에서 같은 경로를 다시 백업하면 첫 백업(조치 전 원본)을 보존하고 건너뛴다 - 예전에는
#   소유자를 바꾼 뒤 두 번째 백업이 첫 백업을 덮어써 원복해도 바뀐 상태가 남았다(U-24/U-31).
fix_backup() {
    _f=$1
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    if [ -e "$_dest" ] || [ -e "$_dest.DIRMETA" ] || [ -e "$_dest.WAS_ABSENT" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    if [ -d "$_f" ]; then
        # 디렉터리는 내용 전체를 복사하지 않고(대부분의 조치는 디렉터리 자체의 소유자/권한만
        # 바꾸므로) 메타데이터(소유자·권한)만 기록해 원복 시 재적용한다. 소유자는 숫자(uid:gid)로
        # 남긴다 - 이름으로 남기면 소유자가 없는 디렉터리(U-15)는 "UNKNOWN" 이 되어 원복 chown 이 실패한다.
        _owner=$(stat -c '%u:%g' "$_f" 2>/dev/null)
        _perm=$(stat -c '%a' "$_f" 2>/dev/null)
        [ -n "$_owner" ] && [ -n "$_perm" ] || fix_abort_item "디렉터리 소유자/권한을 기록할 수 없음: $_f"
        printf '%s\n%s\n' "$_owner" "$_perm" > "$_dest.DIRMETA" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
    elif [ -e "$_f" ]; then
        if ! cp -p "$_f" "$_dest.tmp" 2>/dev/null || ! mv "$_dest.tmp" "$_dest" 2>/dev/null; then
            rm -f "$_dest.tmp" "$_dest"
            fix_abort_item "백업 실패(디스크 공간·권한 확인): $_f"
        fi
        if command -v cmp >/dev/null 2>&1 && ! cmp -s "$_f" "$_dest"; then
            rm -f "$_dest"
            fix_abort_item "백업 검증 실패(원본과 내용이 다름): $_f"
        fi
    else
        : > "$_dest.WAS_ABSENT" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
    fi
}

# fix_backup_owner <경로> — 소유자·권한만 바꾸는 조치용 백업. 내용을 복사하지 않고 숫자 uid:gid 와 권한만
# <백업>.OWNMETA 에 남긴다(심볼릭 링크는 링크 자체 기준). fix_backup 의 cp -p 사본은 원래 소유자를 그대로 가져
# U-15(소유자 없는 파일) 조치의 재검증 find 가 백업 폴더의 사본을 다시 찾아 항상 VULN → 원복되었다.
fix_backup_owner() {
    _f=$1
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    if [ -e "$_dest" ] || [ -e "$_dest.OWNMETA" ] || [ -e "$_dest.DIRMETA" ] || [ -e "$_dest.WAS_ABSENT" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    _owner=$(stat -c '%u:%g' "$_f" 2>/dev/null)
    _perm=$(stat -c '%a' "$_f" 2>/dev/null)
    [ -n "$_owner" ] && [ -n "$_perm" ] || fix_abort_item "소유자/권한을 기록할 수 없음: $_f"
    printf '%s\n%s\n' "$_owner" "$_perm" > "$_dest.OWNMETA" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
}

# fix_backup_remove_path <경로> — 파일/디렉터리를 완전히 삭제하기 전에 내용 전체를 tar로
# 보존한다. fix_backup() 의 디렉터리 처리(소유자/권한 메타데이터만 저장)와 달리, 이 함수는
# "삭제 자체가 조치"인 항목(WEB-07 기본 샘플/매뉴얼 디렉터리 제거 등) 전용으로 내용 전체를
# 백업해 원복 시 삭제 이전 상태로 완전히 복원할 수 있게 한다. tar 가 실패하면 삭제하지 않는다
# (예전에는 tar 실패를 무시하고 rm -rf 해 원본이 영구 소실될 수 있었다).
fix_backup_remove_path() {
    _f=$1
    if [ ! -e "$_f" ] && [ ! -L "$_f" ]; then
        return 0
    fi
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    _parent=$(dirname "$_f")
    _base=$(basename "$_f")
    if ! (cd "$_parent" && tar czf "$_dest.TARBALL.tgz" "$_base") 2>/dev/null || ! tar tzf "$_dest.TARBALL.tgz" >/dev/null 2>&1; then
        rm -f "$_dest.TARBALL.tgz"
        fix_abort_item "삭제 전 백업(tar) 실패 — 삭제하지 않음: $_f"
    fi
    rm -rf "$_f"
}

# ---- 설정 파일 편집 헬퍼 (운영 안전 기준 F2, 1.2.2) ------------------------------------
# fix_write_back <임시파일> <대상파일> — 편집 결과를 mv 대신 "내용만" 덮어써 원래 파일의
# inode·소유자·권한·SELinux 컨텍스트를 유지한다. mv 로 바꾸면 root:root/umask 권한의 새 파일이
# 되어 서비스 계정(tomcat 등)이 못 읽거나 SELinux 라벨이 바뀌어 다음 기동이 실패할 수 있다.
fix_write_back() {
    cat "$1" > "$2" && rm -f "$1"
}

# apache_options_disable <파일> <옵션> — Options 지시어에서 옵션(Indexes/FollowSymLinks/Includes)을
# 끈다. Apache 2.4 는 한 Options 줄에 +/- 가 붙은 옵션과 안 붙은 옵션을 섞으면 문법 오류("Either all
# Options must start with + or -, or no Option may")로 기동에 실패한다 - 예전 조치는 "Options Indexes
# FollowSymLinks" 를 "Options -Indexes FollowSymLinks" 로 바꿔 다음 재시작 때 Apache 가 죽었다.
#   +/- 표기가 없는 줄 → 해당 옵션을 지운다(남는 게 없으면 Options None)
#   +/- 표기가 있는 줄 → 옵션(또는 +옵션)을 지우고 끝에 -옵션 을 붙인다(상위에서 상속된 값까지 끔)
# 1.3.3(F-R5): All(= Indexes Includes FollowSymLinks ExecCGI, MultiViews 제외)은 끌 옵션을 뺀 나머지로 풀어 쓰고,
# Includes 를 끌 때는 IncludesNOEXEC 도 지운다(진단 web_apache_option_hits 와 같은 기준). 예전에는 둘 다 몰라
# WEB-04/12/19 조치가 아무것도 바꾸지 못하고 재검증 VULN → 원복으로 끝났다.
# 바뀐 게 있으면 0, 없으면 1 을 반환한다. 파일 내용만 덮어써 심볼릭 링크(Debian sites-enabled)를 유지한다.
apache_options_disable() {
    _ao_f=$1; _ao_tok=$2
    awk -v tok="$_ao_tok" '
        BEGIN { changed = 0; ltok = tolower(tok); nall = split("Indexes Includes FollowSymLinks ExecCGI", all, " ") }
        function add(t, key) { if (!(key in seen)) { seen[key] = 1; out = out " " t } }
        {
            line = $0
            cr = ""; if (line ~ /\r$/) { cr = "\r"; sub(/\r$/, "", line) }
            lead = line; sub(/[^ \t].*$/, "", lead)
            body = line; sub(/^[ \t]+/, "", body)
            n = split(body, a, /[ \t]+/)
            if (n >= 1 && tolower(a[1]) == "options") {
                signed = 0
                for (i = 2; i <= n; i++) if (a[i] ~ /^[+-]/) signed = 1
                out = ""; hit = 0; split("", seen)
                for (i = 2; i <= n; i++) {
                    t = a[i]
                    if (t == "") continue
                    s = substr(t, 1, 1); w = tolower(t)
                    if (s == "+" || s == "-") w = substr(w, 2); else s = ""
                    if (s == "-") { add(t, "-" w); continue }
                    if (w == "all") {
                        hit = 1
                        for (k = 1; k <= nall; k++)
                            if (tolower(all[k]) != ltok) add((signed ? "+" : "") all[k], tolower(all[k]))
                        continue
                    }
                    if (w == ltok || (ltok == "includes" && w == "includesnoexec")) { hit = 1; continue }
                    add(t, w)
                }
                if (hit) {
                    if (signed) add("-" tok, "-" ltok)
                    if (out == "") out = " None"
                    line = lead a[1] out
                    changed = 1
                }
            }
            print line cr
        }
        END { exit(changed ? 0 : 1) }
    ' "$_ao_f" > "$_ao_f.kisa_tmp"
    _ao_rc=$?
    if [ "$_ao_rc" -eq 0 ]; then fix_write_back "$_ao_f.kisa_tmp" "$_ao_f"; else rm -f "$_ao_f.kisa_tmp"; fi
    return "$_ao_rc"
}

# apache_options_enabled <파일> <옵션> — 주석이 아닌 Options 줄에 옵션이 켜져(무표기·+옵션·All, Includes 는
# IncludesNOEXEC 포함) 있으면 0. 진단의 web_apache_option_hits 와 같은 기준(1.3.3, F-R5).
apache_options_enabled() {
    [ -n "$(web_apache_option_hits "$2" "$1")" ]
}

# fix_sed_inplace <파일> <sed 인자...> — 모든 조치(fixes/*)에서 sed -i 대신 쓴다(X-07, 1.3.4 에 03_web 의
# web_sed_inplace 를 공통화). sed -i 는 새 파일을 만들어 바꿔치기하므로 심볼릭 링크를 일반 파일로 바꿔 버린다 -
# Debian 의 sites-enabled/mods-enabled 링크(fix_safety 실기로 발견), RHEL 의 /etc/pam.d/system-auth →
# authselect 링크 등. 링크 대상은 그대로 남아 원복(cp -p 로 링크 경로에 덮어씀)해도 링크가 돌아오지 않고,
# 소유자·권한·SELinux 라벨·inode 도 바뀔 수 있다. 결과를 fix_write_back 으로 내용만 덮어써(cat > 경로 는 링크를
# 따라가 대상 파일에 씀) 링크·inode·소유자를 유지한다. sed 실패 시 원본을 건드리지 않고 1.
# CI(static-analysis)가 */fixes/ 에 sed -i 가 다시 들어오면 실패시킨다.
fix_sed_inplace() {
    _fsi_f=$1; shift
    if sed "$@" "$_fsi_f" > "$_fsi_f.kisa_tmp" 2>/dev/null; then
        fix_write_back "$_fsi_f.kisa_tmp" "$_fsi_f"
    else
        rm -f "$_fsi_f.kisa_tmp"; return 1
    fi
}

# nginx_http_insert <파일> <지시어 줄> — 첫 "http {" 블록 바로 안쪽에 지시어를 넣는다. server_tokens /
# error_page / disable_symlinks 는 http·server·location 컨텍스트에서만 허용되는데, 예전 조치는 파일
# 맨 앞(1i)이나 맨 끝(main 컨텍스트)에 넣어 "directive is not allowed here" 로 다음 reload/재시작이
# 실패했다. http 블록을 찾지 못하면 아무것도 바꾸지 않고 1 을 반환한다(수동 조치 안내).
nginx_http_insert() {
    _ni_f=$1; _ni_line=$2
    grep -qE '^[[:space:]]*http[[:space:]]*\{' "$_ni_f" 2>/dev/null || return 1
    awk -v ins="$_ni_line" '
        !done && /^[ \t]*http[ \t]*\{/ { print; print "    # KISA 조치"; print "    " ins; done = 1; next }
        { print }
    ' "$_ni_f" > "$_ni_f.kisa_tmp" && fix_write_back "$_ni_f.kisa_tmp" "$_ni_f"
}

# web_config_test <apache|nginx> — 설정 문법 검사. 0=통과, 1=실패(WEB_CONFIG_TEST_OUT 에 출력),
# 2=검사 도구 없음. 실행 중인 서버에는 영향이 없다(설정 파일만 파싱).
web_config_test() {
    WEB_CONFIG_TEST_OUT=""
    case "$1" in
        apache)
            for _t in apachectl apache2ctl httpd; do
                command -v "$_t" >/dev/null 2>&1 || continue
                WEB_CONFIG_TEST_OUT=$("$_t" -t 2>&1) && return 0
                return 1
            done
            return 2 ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || return 2
            WEB_CONFIG_TEST_OUT=$(nginx -t 2>&1) && return 0
            return 1 ;;
    esac
    return 2
}

# sshd_global_lines [설정파일] — sshd 가 전역(Match 블록 밖)으로 읽는 설정 줄을 "읽는 순서대로"
# 출력한다. Include 를 펼치고(상대경로는 /etc/ssh 기준), 각 파일에서 Match 이후는 제외한다.
# sshd 는 같은 키워드가 여러 번 나오면 **처음 값**을 쓴다(sshd_config(5)) - 마지막 값을 보면
# sshd_config.d 드롭인에서 먼저 지정된 값을 놓쳐 오판한다.
_sshd_filter_global() {
    awk '{ sub(/^[ \t]+/, ""); if ($0 == "" || substr($0, 1, 1) == "#") next
           k = tolower($1); if (k == "match") exit
           if (k == "include") { $1 = ""; print "@@INCLUDE" $0; next }
           print }' "$1" 2>/dev/null
}
sshd_global_lines() {
    _sg_cfg=${1:-/etc/ssh/sshd_config}
    [ -f "$_sg_cfg" ] || return 0
    _sshd_filter_global "$_sg_cfg" | while IFS= read -r _sg_l; do
        case "$_sg_l" in
            @@INCLUDE*)
                set -f
                # shellcheck disable=SC2086
                set -- ${_sg_l#@@INCLUDE}
                set +f
                for _sg_p in "$@"; do
                    case "$_sg_p" in /*) : ;; *) _sg_p="/etc/ssh/$_sg_p" ;; esac
                    # shellcheck disable=SC2086
                    for _sg_inc in $_sg_p; do
                        [ -f "$_sg_inc" ] && _sshd_filter_global "$_sg_inc" | grep -v '^@@INCLUDE'
                    done
                done ;;
            *) printf '%s\n' "$_sg_l" ;;
        esac
    done
}

# sshd_effective_value <키워드> — 실제로 적용되는 전역 값을 SSHD_VALUE 에, 근거를 SSHD_VALUE_SOURCE 에
# 담는다($(...) 로 부르면 서브셸이라 근거 변수가 전달되지 않으므로 출력 대신 변수로 돌려준다).
# sshd -T(유효 설정 출력)가 되면 그 값을, 안 되면(권한 부족·/run/sshd 없음 등) 파일 분석 첫 값을 쓴다.
sshd_effective_value() {
    _se_k=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    SSHD_VALUE=""
    if command -v sshd >/dev/null 2>&1; then
        SSHD_VALUE=$(run_to 15 sshd -T 2>/dev/null | awk -v k="$_se_k" '$1 == k { print $2; exit }')
        if [ -n "$SSHD_VALUE" ]; then SSHD_VALUE_SOURCE="sshd -T(실제 적용 값)"; return 0; fi
    fi
    SSHD_VALUE_SOURCE="설정 파일 분석(Include 반영, 처음 나온 값 우선)"
    SSHD_VALUE=$(sshd_global_lines | awk -v k="$_se_k" 'tolower($1) == k { print $2; exit }')
}

# sshd_match_overrides <키워드> — Match 블록 안에서 키워드를 지정한 줄(파일:내용). 전역은 no 여도
# 특정 사용자/주소에 예외를 둔 경우를 드러내기 위함.
sshd_match_overrides() {
    _so_k=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for _so_f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$_so_f" ] || continue
        awk -v k="$_so_k" -v f="$_so_f" '{ s = $0; sub(/^[ \t]+/, "", s); if (s == "" || substr(s, 1, 1) == "#") next
            split(s, a, /[ \t]+/); if (tolower(a[1]) == "match") m = 1
            else if (m && tolower(a[1]) == k) print f ": " s }' "$_so_f"
    done
}

# ---- 비밀번호 변경 조치 헬퍼 (1.3.0, 사용자 결정: 무작위 생성 폐지 → 사전 승인 + 직접 입력) ----------
# 예전 조치(mysql D-01/D-08, postgres D-01, WEB-02)는 무작위 비밀번호를 만들어 아무 데도 기록하지 않아
# 앱·관리 접속이 끊기고 아무도 새 값을 몰랐다. 이제 계정마다 승인을 받고 운영자가 새 비밀번호를
# 터미널에서 직접 입력한다. 비대화형이면 아무것도 바꾸지 않는다. 비밀번호는 인자·로그·백업에 남기지 않는다.

# fix_tty_available — 제어 터미널을 실제로 열 수 있으면 0(/dev/tty 파일이 있어도 cron/docker 에선 열기 실패)
fix_tty_available() {
    ( : < /dev/tty ) 2>/dev/null
}

# fix_confirm_tty <질문> — 터미널에서 y/N(파이프 입력으로는 승인 불가). 비대화형이면 1.
fix_confirm_tty() {
    fix_tty_available || return 1
    printf '%s [y/N] ' "$1" > /dev/tty
    _ct=""
    IFS= read -r _ct < /dev/tty || _ct=""
    case "$_ct" in y|Y) return 0 ;; esac
    return 1
}

# fix_read_new_password <대상 설명> — 새 비밀번호를 화면 표시 없이 2회 입력받아 FIX_NEW_PASSWORD 에 담는다.
# 8자 미만·불일치는 다시 묻고(최대 3회), 끝내 실패하거나 비대화형이면 1(변경하지 않음).
# 호출부는 사용 직후 FIX_NEW_PASSWORD="" 로 지운다.
fix_read_new_password() {
    FIX_NEW_PASSWORD=""
    fix_tty_available || return 1
    _rp_try=0
    while [ "$_rp_try" -lt 3 ]; do
        _rp_try=$((_rp_try + 1))
        printf '  %s 새 비밀번호(화면에 표시되지 않음, 8자 이상): ' "$1" > /dev/tty
        stty -echo < /dev/tty 2>/dev/null
        _rp1=""; IFS= read -r _rp1 < /dev/tty || _rp1=""
        stty echo < /dev/tty 2>/dev/null; printf '\n' > /dev/tty
        printf '  한 번 더 입력: ' > /dev/tty
        stty -echo < /dev/tty 2>/dev/null
        _rp2=""; IFS= read -r _rp2 < /dev/tty || _rp2=""
        stty echo < /dev/tty 2>/dev/null; printf '\n' > /dev/tty
        if [ "${#_rp1}" -lt 8 ]; then
            printf '  8자 이상이어야 합니다.\n' > /dev/tty
        elif [ "$_rp1" != "$_rp2" ]; then
            printf '  두 입력이 다릅니다.\n' > /dev/tty
        else
            FIX_NEW_PASSWORD=$_rp1; _rp1=""; _rp2=""
            return 0
        fi
    done
    _rp1=""; _rp2=""
    printf '  비밀번호를 설정하지 않고 건너뜁니다.\n' > /dev/tty
    return 1
}

# sql_quote_mysql / sql_quote_pg <값> — SQL 문자열 리터럴('...') 안에 넣을 수 있게 이스케이프한다.
# 운영자가 입력한 비밀번호에 ' 나 \ 가 있어도 SQL 이 깨지거나 다른 문장이 실행되지 않게 한다.
sql_quote_mysql() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}
sql_quote_pg() {
    printf '%s' "$1" | sed -e "s/'/''/g"
}

# db_exec_stdin <mysql|postgres> <sql> — 비밀번호가 들어간 SQL 을 명령 인자(-e/-c)가 아니라 표준입력으로
# 보낸다. 인자로 넘기면 실행되는 동안 ps 로 다른 사용자에게도 보인다.
db_exec_stdin() {
    _db_conn_blocked && return 1
    case "$1" in
        mysql)
            (
                [ -n "${DB_PASSWORD:-}" ] && export MYSQL_PWD="$DB_PASSWORD"
                # shellcheck disable=SC2046
                printf '%s\n' "$2" | _db_run mysql $(mysql_args)
            ) 2>"${DB_ERR_FILE:-/dev/null}" ;;
        postgres)
            (
                [ -n "${DB_PASSWORD:-}" ] && export PGPASSWORD="$DB_PASSWORD"
                export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
                # shellcheck disable=SC2046
                printf '%s\n' "$2" | _db_run psql $(psql_args) -v ON_ERROR_STOP=1
            ) 2>"${DB_ERR_FILE:-/dev/null}" ;;
        *) return 1 ;;
    esac
}

# ---- fix 진입점 공통 가드 (운영 안전 기준 F1·F6, 1.2.2) ------------------------------
# fix_require_root — 적용/원복을 root 로만 허용한다. 권한이 모자라면 일부 파일만 바뀌고
# 원복(chown/cp -p)도 실패해 "반쯤 바뀐" 상태가 남기 때문이다. 08_dbms 는 Oracle OS 인증
# (oracle 계정/dba 그룹)으로 실행해야 해 이 가드를 쓰지 않는다.
fix_require_root() {
    [ "$(id -u 2>/dev/null)" = "0" ] && return 0
    log_error "조치 적용/원복은 root 권한이 필요합니다(권한 부족으로 일부만 바뀌거나 원복이 실패하는 것을 막기 위해 중단, 변경 없음)."
    exit 2
}

# fix_lock_acquire <out_base> <category_num> — 같은 카테고리의 조치가 동시에 돌면 서로의 백업을
# 덮어쓰고 같은 파일을 번갈아 고치므로 원자적 mkdir 잠금으로 막는다. 종료 시 fix_lock_release.
fix_lock_acquire() {
    ( umask 077; mkdir -p "$1" ) 2>/dev/null
    FIX_LOCK_DIR="$1/.fix_$2.lock"
    if ! mkdir "$FIX_LOCK_DIR" 2>/dev/null; then
        _lpid=$(cat "$FIX_LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_lpid" ] && kill -0 "$_lpid" 2>/dev/null; then
            log_error "다른 조치(fix) 실행이 진행 중입니다(PID $_lpid). 끝난 뒤 다시 실행하세요. (잠금: $FIX_LOCK_DIR)"
            FIX_LOCK_DIR=""
            exit 2
        fi
        log_warn "이전 실행이 남긴 잠금을 정리합니다(PID ${_lpid:-알 수 없음}, 실행 중 아님)."
        rm -rf "$FIX_LOCK_DIR"
        mkdir "$FIX_LOCK_DIR" 2>/dev/null || { log_error "잠금을 만들 수 없습니다: $FIX_LOCK_DIR"; FIX_LOCK_DIR=""; exit 2; }
    fi
    echo $$ > "$FIX_LOCK_DIR/pid"
}

fix_lock_release() {
    [ -n "${FIX_LOCK_DIR:-}" ] && rm -rf "$FIX_LOCK_DIR"
    FIX_LOCK_DIR=""
}

# fix_confirm_plan <코드...> — --apply 시 실제로 바뀔 항목을 먼저 모두 보여주고 1회 확인받는다.
# auto 등급은 항목별 확인 없이 적용되므로, 예전처럼 --apply 만 붙이면 경고 없이 auto 전체가
# 적용되던 문제를 막는다. --yes(YES=1)는 이 1회 확인만 생략한다(confirm 등급은 여전히 항목별 확인).
# 비대화형(터미널 없음)에서 --yes 없이 실행하면 아무것도 바꾸지 않고 끝낸다.
# fix_rollback_note <조치 파일> — 조치 파일 머리말의 "# 원복: ..." 표기. 없으면 빈 값(= 백업으로 원복 가능).
# 원복할 수 없거나 일부만 되돌아가는 조치를 적용 "전에" 알리기 위함(운영 안전 기준 F4).
fix_rollback_note() {
    [ -f "$1" ] && sed -n '1,12s/^# 원복: //p' "$1" | head -n1
}
# fix_change_note <조치 파일> — 조치 파일 머리말의 "# 변경: ..." 표기(무엇을 어떤 값으로 바꾸는지). dry-run·적용 전 확인 목록에
# 보여 준다(실무 적용 검증 P-24 - 예전에는 등급만 보여 실제로 바뀔 값을 적용 전에 알 수 없었다). lib/tests/guide_consistency.py 가 필수로 검사.
fix_change_note() {
    [ -f "$1" ] && sed -n '1,12s/^# 변경: //p' "$1" | head -n1
}

# fix_impact_note <조치 파일> — 조치 파일 머리말의 "# 영향: ..." 표기(1.6.0 G-02). 적용하는 순간 운영 중인 업무가 끊길 수 있는
# 조치(서비스·프로세스 중지, 세션 끊김, 계정 잠금·쉘 변경, 쓰는 중인 접근 차단, 서비스 재시작)만 붙인다(F5). 없으면 빈 값.
fix_impact_note() {
    [ -f "$1" ] && sed -n '1,12s/^# 영향: //p' "$1" | head -n1
}

# ---- 조치 정책 모드 (1.6.0 G-01·G-02·G-03) ------------------------------------------------------------
# fix.sh --policy <파일> --operator <이름>: 승인된 항목만 묻지 않고 적용한다(무인 조치). 정책 파일은 sh·PowerShell·Python 이
# 같은 규칙으로 읽는 줄 단위 텍스트다(UTF-8, BOM·CRLF 허용, 줄 앞뒤 공백 무시, 맨 앞 # 은 주석):
#   머리말(첫 [host: 앞): category=<01|02|03|05|07|08> · expires=YYYY-MM-DD(그날까지 유효) · approver=<이름> 각 정확히 1회,
#                        승인 코드 한 줄씩 "코드" 또는 "코드:irreversible"(guide.json 에 있는 코드만, 중복 금지). 다른 키=값 은 거부.
#   [host:이름] 구역   : "-코드" 줄만(그 호스트에서 제외, 이름은 대소문자 무시). [host:*] 는 이름이 맞는 구역이 없는 모든 호스트.
#   실행 호스트(host_name)와 같은 구역 → 없으면 [host:*] → 둘 다 없으면 거부. 형식 오류는 줄 번호와 함께 보고하고 exit 2(변경 없음).
# G-02: 머리말에 "# 원복:"(F4) 또는 "# 영향:"(F5) 이 있는 조치는 정책에 "코드:irreversible" 로 적혀 있어야 적용한다.
# 정책은 확인(fix_confirm_plan·confirm 등급 y/N)만 대신한다 - X-06(fix_check_result_target)·비밀번호 직접 입력(터미널 필요)은 그대로.
POLICY_SET=0; POLICY_FILE=""; POLICY_OPERATOR=""; POLICY_OPERATOR_SET=0
POLICY_CODES=" "; POLICY_IRREV=" "; POLICY_EXCL=" "; POLICY_SECTION=""; POLICY_APPROVER=""; POLICY_EXPIRES=""
POLICY_SHA256=""; POLICY_ABS=""; POLICY_HOST=""; POLICY_REASON=""; AUDIT_FILE=""

# fix_policy_args_check <ROLLBACK_DIR> — 옵션 조합 확인(fix.sh 가 옵션 해석 직후 부른다). 잘못되면 변경 없이 exit 2.
fix_policy_args_check() {
    if [ "$POLICY_OPERATOR_SET" -eq 1 ] && [ "$POLICY_SET" -ne 1 ]; then
        log_error "--operator 는 --policy <정책 파일> 과 함께만 씁니다(변경 없음)."; exit 2
    fi
    [ "$POLICY_SET" -eq 1 ] || return 0
    # 원복(--rollback)은 정책과 무관하다 - 정책 옵션은 무시하고 원복만 한다(sh·PowerShell 공통 해석)
    if [ -n "${1:-}" ]; then
        log_warn "--rollback 에서는 --policy/--operator 를 쓰지 않습니다(무시하고 원복만 진행)."
        POLICY_SET=0; return 0
    fi
    if [ -z "$POLICY_FILE" ]; then log_error "--policy 에 정책 파일 경로가 필요합니다(변경 없음)."; exit 2; fi
    _pa_op=$(printf '%s' "$POLICY_OPERATOR" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ -z "$_pa_op" ]; then
        log_error "정책 모드(--policy)에는 실제 실행자 이름 --operator <이름> 이 필요합니다(감사 기록 G-03, 변경 없음)."; exit 2
    fi
    # 감사 기록이 키=값 한 줄이라 줄바꿈·탭이 들어간 이름은 받지 않는다(기록 위조 방지)
    _pa_nl='
'
    case "$_pa_op" in *"$_pa_nl"*)
        log_error "--operator 이름에 제어 문자(줄바꿈·탭 등)를 쓸 수 없습니다(변경 없음)."; exit 2 ;;
    esac
    if [ "$(printf '%s' "$_pa_op" | tr -d '\001-\037\177')" != "$_pa_op" ]; then
        log_error "--operator 이름에 제어 문자(줄바꿈·탭 등)를 쓸 수 없습니다(변경 없음)."; exit 2
    fi
    POLICY_OPERATOR=$_pa_op
    return 0
}

# fix_sha256 <파일> — SHA-256 16진수(소문자). sha256sum → shasum -a 256 → openssl 순서, 셋 다 없으면 1.
fix_sha256() {
    _sh_v=""
    if command -v sha256sum >/dev/null 2>&1; then _sh_v=$(sha256sum < "$1" 2>/dev/null | awk '{ print $1 }')
    elif command -v shasum >/dev/null 2>&1; then _sh_v=$(shasum -a 256 < "$1" 2>/dev/null | awk '{ print $1 }')
    elif command -v openssl >/dev/null 2>&1; then _sh_v=$(openssl dgst -sha256 < "$1" 2>/dev/null | awk '{ print $NF }')
    fi
    _sh_v=$(printf '%s' "$_sh_v" | tr '[:upper:]' '[:lower:]')
    case "$_sh_v" in ????????????????????????????????????????????????????????????????) ;; *) return 1 ;; esac
    case "$_sh_v" in *[!0-9a-f]*) return 1 ;; esac
    printf '%s\n' "$_sh_v"
}

# _policy_parse <정책 파일> <카테고리 번호> <guide.json> <호스트> <오늘 YYYY-MM-DD> — 정책 파일을 검증·해석한다(표준출력).
#   오류: "ERR<TAB>줄 번호(또는 -)<TAB>사유" 줄(하나라도 있으면 거부) / 정상: APPROVER·EXPIRES·SECTION·CODE<TAB>코드<TAB>irreversible(0|1)<TAB>제외(0|1)
# 줄 번호는 파일의 실제 줄(주석·빈 줄 포함, 1부터). 바이트 단위(LC_ALL=C)라 호스트 이름 대소문자 무시는 ASCII 만 해당한다.
_policy_parse() {
    awk -v cat="$2" -v codes="$(guide_list_codes "$3" | tr '\n' ' ')" -v host="$4" -v today="$5" -v bom="$(printf '\357\273\277')" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function err(ln, msg) { print "ERR\t" ln "\t" msg; nerr++ }
        function isdate(s,   y, m, d) {
            if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
            m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
            return (m >= 1 && m <= 12 && d >= 1 && d <= 31)
        }
        BEGIN { n = split(codes, cl, " "); for (i = 1; i <= n; i++) valid[cl[i]] = 1; insect = 0; na = 0; nerr = 0 }
        {
            line = $0
            if (NR == 1 && substr(line, 1, 3) == bom) line = substr(line, 4)
            sub(/\r$/, "", line)
            line = trim(line)
            if (line == "" || substr(line, 1, 1) == "#") next
            if (substr(line, 1, 1) == "[") {
                if (line !~ /^\[host:[^]]*\]$/) { err(NR, "구역 형식 오류(허용: [host:이름]): " line); next }
                oname = trim(substr(line, 7, length(line) - 7)); name = tolower(oname)
                if (name == "") { err(NR, "호스트 이름이 비어 있음: " line); next }
                if (name in sect) err(NR, "같은 호스트 구역이 두 번 나옴: " line)
                else orig[name] = oname
                sect[name] = 1; cur = name; insect = 1; next
            }
            if (insect) {
                if (line !~ /^-[A-Z]+-[0-9]+$/) { err(NR, "호스트 구역에는 \"-코드\" 줄만 쓸 수 있음: " line); next }
                c = substr(line, 2)
                if (!(c in valid)) err(NR, "이 카테고리 guide.json 에 없는 코드: " c)
                else if ((cur, c) in excl) err(NR, "같은 구역에서 같은 코드를 두 번 제외함: " c)
                excl[cur, c] = 1; next
            }
            p = index(line, "=")
            if (p > 0) {
                k = trim(substr(line, 1, p - 1)); v = trim(substr(line, p + 1))
                if (k != "category" && k != "expires" && k != "approver") { err(NR, "알 수 없는 키: " k); next }
                if (k in hdr) { err(NR, k "= 가 두 번 나옴"); next }
                hdr[k] = v; hl[k] = NR; next
            }
            c = line; irr = 0
            if (c ~ /:irreversible$/) { c = substr(c, 1, length(c) - 13); irr = 1 }
            if (c !~ /^[A-Z]+-[0-9]+$/) { err(NR, "형식 오류(코드 또는 코드:irreversible 이어야 함): " line); next }
            if (!(c in valid)) { err(NR, "이 카테고리 guide.json 에 없는 코드: " c); next }
            if (c in appr) { err(NR, "같은 코드가 두 번 나옴: " c); next }
            appr[c] = irr; order[++na] = c
        }
        END {
            if (!("category" in hdr)) err("-", "머리말에 category= 가 없음")
            else if (hdr["category"] != cat) err(hl["category"], "category=" hdr["category"] " 는 이 조치 카테고리(" cat ")와 다름")
            if (!("expires" in hdr)) err("-", "머리말에 expires= 가 없음")
            else if (!isdate(hdr["expires"])) err(hl["expires"], "expires 는 YYYY-MM-DD 형식이어야 함: " hdr["expires"])
            else if (today > hdr["expires"]) err(hl["expires"], "정책 유효기간이 지났음(expires=" hdr["expires"] ", 오늘 " today ")")
            if (!("approver" in hdr)) err("-", "머리말에 approver= 가 없음")
            else if (hdr["approver"] == "") err(hl["approver"], "approver 가 비어 있음")
            if (nerr) exit
            lh = tolower(host)
            if (lh in sect) s = lh
            else if ("*" in sect) s = "*"
            else { err("-", "정책에 없는 호스트: " host " ([host:" host "] 또는 [host:*] 구역 필요)"); exit }
            print "APPROVER\t" hdr["approver"]; print "EXPIRES\t" hdr["expires"]; print "SECTION\t" orig[s]
            for (i = 1; i <= na; i++) { c = order[i]; print "CODE\t" c "\t" appr[c] "\t" (((s, c) in excl) ? 1 : 0) }
        }
    ' "$1"
}

# fix_policy_load — --policy 가 있으면 정책 파일을 읽어 POLICY_* 를 채운다(GUIDE_JSON·CATEGORY_NUM 필요). 거부 사유가 있으면
# 줄 번호와 함께 모두 보여 주고 exit 2(아무것도 바꾸지 않음). SHA-256 도구가 없으면 감사 기록을 남길 수 없어 거부(G-03).
fix_policy_load() {
    [ "$POLICY_SET" -eq 1 ] || return 0
    if [ ! -f "$POLICY_FILE" ] || [ ! -r "$POLICY_FILE" ]; then
        log_error "정책 파일을 읽을 수 없습니다(변경 없음): $POLICY_FILE"; exit 2
    fi
    if [ ! -f "$GUIDE_JSON" ]; then log_error "$GUIDE_JSON 이 없습니다."; exit 2; fi
    POLICY_SHA256=$(fix_sha256 "$POLICY_FILE") || {
        log_error "SHA-256 도구(sha256sum/shasum/openssl)가 없어 정책 파일 지문을 감사 기록에 남길 수 없습니다 - 정책 모드를 쓸 수 없습니다(변경 없음)."
        exit 2
    }
    POLICY_ABS="$(cd "$(dirname "$POLICY_FILE")" && pwd)/$(basename "$POLICY_FILE")"
    POLICY_HOST=$(host_name)
    _pl_out=$(_policy_parse "$POLICY_FILE" "$CATEGORY_NUM" "$GUIDE_JSON" "$POLICY_HOST" "$(date '+%Y-%m-%d')")
    _pl_tab=$(printf '\t')
    if printf '%s\n' "$_pl_out" | grep -q "^ERR$_pl_tab"; then
        printf '%s\n' "$_pl_out" | grep "^ERR$_pl_tab" | while IFS="$_pl_tab" read -r _pl_x _pl_ln _pl_msg; do
            log_error "정책 파일 거부($POLICY_FILE:$_pl_ln): $_pl_msg"
        done
        log_error "정책 파일을 고친 뒤 다시 실행하세요 - 아무것도 변경하지 않았습니다."
        exit 2
    fi
    POLICY_CODES=" "; POLICY_IRREV=" "; POLICY_EXCL=" "
    while IFS="$_pl_tab" read -r _pl_k _pl_a _pl_b _pl_c; do
        case "$_pl_k" in
            APPROVER) POLICY_APPROVER=$_pl_a ;;
            EXPIRES) POLICY_EXPIRES=$_pl_a ;;
            SECTION) POLICY_SECTION=$_pl_a ;;
            CODE)
                POLICY_CODES="$POLICY_CODES$_pl_a "
                [ "$_pl_b" = "1" ] && POLICY_IRREV="$POLICY_IRREV$_pl_a "
                [ "$_pl_c" = "1" ] && POLICY_EXCL="$POLICY_EXCL$_pl_a " ;;
        esac
    done <<EOF
$_pl_out
EOF
    return 0
}

# fix_policy_approved <코드> — 정책 모드에서 이 호스트에 승인된 코드면 0. 아니면 1 + POLICY_REASON. 정책 모드가 아니면 항상 0.
fix_policy_approved() {
    POLICY_REASON=""
    [ "$POLICY_SET" -eq 1 ] || return 0
    case "$POLICY_CODES" in *" $1 "*) ;; *) POLICY_REASON="정책 미승인"; return 1 ;; esac
    case "$POLICY_EXCL" in *" $1 "*) POLICY_REASON="정책 미승인(호스트 제외: [host:$POLICY_SECTION])"; return 1 ;; esac
    return 0
}

# fix_policy_irrev_ok <코드> <조치 파일> — G-02: 머리말에 원복/영향 표기가 있는 조치는 정책에 코드:irreversible 이 있어야 0.
fix_policy_irrev_ok() {
    POLICY_REASON=""
    [ "$POLICY_SET" -eq 1 ] || return 0
    _pi_rb=$(fix_rollback_note "$2"); _pi_im=$(fix_impact_note "$2")
    [ -n "$_pi_rb" ] || [ -n "$_pi_im" ] || return 0
    case "$POLICY_IRREV" in *" $1 "*) return 0 ;; esac
    POLICY_REASON="irreversible 플래그 필요: ${_pi_rb:+원복: $_pi_rb}${_pi_rb:+${_pi_im:+ / }}${_pi_im:+영향: $_pi_im}"
    return 1
}

# fix_iso_now — ISO 8601 로컬 시각 + 오프셋(2026-11-09T10:00:00+09:00)
fix_iso_now() {
    date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

# fix_login_user — 실제 로그인 사용자(G-03): SUDO_USER → logname → id -un
fix_login_user() {
    if [ -n "${SUDO_USER:-}" ]; then printf '%s\n' "$SUDO_USER"; return; fi
    _lu=$(logname 2>/dev/null) && [ -n "$_lu" ] && { printf '%s\n' "$_lu"; return; }
    id -un 2>/dev/null || echo unknown
}

# fix_audit_begin — 정책 모드 감사 기록(G-03)을 audit.txt(키=값, BOM 없는 UTF-8)와 FIX_LOG 맨 앞("# 키=값" 주석 줄)에 남긴다
# (fix_prepare_dir 가 부른다). 종료 건수 키(fix_audit_finish)는 PowerShell 과 같다: applied·failed·declined·skipped·manual·preview·
# policy_skipped·failed_codes(콤마 구분) + sh 전용 partial(일부 적용, 남은 부분 수동).
# 비밀값은 쓰지 않는다(S5) - 실행자·승인자 이름, 정책 경로·지문, 시각, 대상만.
fix_audit_begin() {
    [ "$POLICY_SET" -eq 1 ] || return 0
    AUDIT_FILE="$FIX_OUT_DIR/audit.txt"
    {
        printf 'operator=%s\n' "$POLICY_OPERATOR"
        printf 'login_user=%s\n' "$(fix_login_user)"
        printf 'approver=%s\n' "$POLICY_APPROVER"
        printf 'policy_file=%s\n' "$POLICY_ABS"
        printf 'policy_sha256=%s\n' "$POLICY_SHA256"
        printf 'policy_expires=%s\n' "$POLICY_EXPIRES"
        printf 'policy_host_section=%s\n' "$POLICY_SECTION"
        printf 'started_at=%s\n' "$(fix_iso_now)"
        printf 'host=%s\n' "$(host_name)"
        printf 'category=%s\n' "$CATEGORY_NUM"
        printf 'mode=%s\n' "$([ "${APPLY:-0}" -eq 1 ] && echo apply || echo dry-run)"
        printf 'tool_version=%s\n' "$TOOL_VERSION"
    } > "$AUDIT_FILE"
    sed 's/^/# /' "$AUDIT_FILE" >> "$FIX_LOG"
}

# fix_audit_finish [aborted 사유] — 종료 시각과 건수 요약을 audit.txt·FIX_LOG 끝에 남긴다.
fix_audit_finish() {
    [ "$POLICY_SET" -eq 1 ] && [ -n "$AUDIT_FILE" ] || return 0
    {
        printf 'finished_at=%s\n' "$(fix_iso_now)"
        [ -n "${1:-}" ] && printf 'aborted=%s\n' "$1"
        printf 'applied=%s\nfailed=%s\ndeclined=%s\nskipped=%s\nmanual=%s\npreview=%s\npolicy_skipped=%s\npartial=%s\n' \
            "${N_APPLIED:-0}" "${N_FAILED:-0}" "${N_DECLINED:-0}" "${N_SKIPPED:-0}" "${N_MANUAL:-0}" "${N_PREVIEW:-0}" "${N_POLICY_SKIPPED:-0}" "${N_PARTIAL:-0}"
        printf 'failed_codes=%s\n' "$(printf '%s' "${FAILED_CODES:-}" | sed 's/^ //; s/ /,/g')"
    } > "$AUDIT_FILE.end"
    cat "$AUDIT_FILE.end" >> "$AUDIT_FILE"; sed 's/^/# /' "$AUDIT_FILE.end" >> "$FIX_LOG"; rm -f "$AUDIT_FILE.end"
}

# fix_policy_banner — 정책 모드면 실행 배너에 정책 요약 한 줄
fix_policy_banner() {
    [ "$POLICY_SET" -eq 1 ] || return 0
    echo "정책       : $POLICY_ABS (승인자 $POLICY_APPROVER, ~$POLICY_EXPIRES, 구역 [host:$POLICY_SECTION], 실행자 $POLICY_OPERATOR) - 승인 항목만, 확인 없이"
    echo "감사 기록  : ${AUDIT_FILE:-없음}"
}

fix_confirm_plan() {
    [ "$POLICY_SET" -eq 1 ] && return 0
    [ "${YES:-0}" -eq 1 ] && return 0
    echo "다음 항목을 실제로 변경합니다:"
    _n_auto=0
    for _c in "$@"; do
        _g=$(guide_field "$GUIDE_JSON" "$_c" "fix"); [ -z "$_g" ] && _g="manual"
        _t=$(guide_field "$GUIDE_JSON" "$_c" "title")
        _rb=$(fix_rollback_note "${FIX_FILE_DIR:-.}/$_c.sh")
        _chg=$(fix_change_note "${FIX_FILE_DIR:-.}/$_c.sh")
        _imp=$(fix_impact_note "${FIX_FILE_DIR:-.}/$_c.sh")
        case "$_g" in
            auto) printf '  [auto]    %-8s %s  ← 개별 확인 없이 적용\n' "$_c" "$_t"; _n_auto=$((_n_auto + 1)) ;;
            confirm) printf '  [confirm] %-8s %s  ← 적용 직전 항목별로 다시 확인\n' "$_c" "$_t" ;;
        esac
        case "$_g" in auto|confirm)
            [ -n "$_chg" ] && printf '            └ 변경: %s\n' "$_chg"
            [ -n "$_rb" ] && printf '            └ 원복: %s\n' "$_rb"
            [ -n "$_imp" ] && printf '            └ 영향: %s\n' "$_imp" ;;
        esac
    done
    printf '위 목록대로 진행하시겠습니까? (auto %s건은 추가 확인 없이 적용됨) [y/N] ' "$_n_auto"
    _ans=""
    read -r _ans < /dev/tty 2>/dev/null || _ans=""
    case "$_ans" in
        y|Y) return 0 ;;
        *) echo; echo "중단 — 아무것도 변경하지 않았습니다. (비대화형 실행은 --yes 로 이 확인을 생략할 수 있음)"; exit 0 ;;
    esac
}

# fix_rollback_item <코드> — 해당 항목에서 백업한 SQL·파일·서비스 상태를 원상 복구한다.
# 실패한 원복은 FIX_ROLLBACK_FAILS 에 누적한다(운영 안전 기준 F4) - 예전에는 모든 오류를 삼키고 항상
# "원복 완료"로 표시해, 실제로 되돌아가지 않은 변경을 운영자가 알 수 없었다. 파이프(| while)는 서브셸이라
# 실패 집계가 전달되지 않으므로 here-doc 반복문을 쓴다.
FIX_ROLLBACK_FAILS=""
_rb_fail() { FIX_ROLLBACK_FAILS="$FIX_ROLLBACK_FAILS
[$_code] $1"; }
fix_rollback_item() {
    _code=$1
    _dir="$FIX_BACKUP_DIR/$_code"
    [ -d "$_dir" ] || return 0

    # DBMS SQL 원복은 파일 원복과 메커니즘이 완전히 달라(DB_* 접속 환경변수를 이용해 실제 SQL을
    # 재실행) 별도로 먼저 처리한다. 같은 항목 안에서 여러 SQL을 순서대로 큐에 넣었을 수 있으므로
    # (예: 계정 3개를 순서대로 잠금) 적용 역순(번호 내림차순)으로 실행한다. "--" 로 시작하는 큐는
    # 원복 SQL 이 없다는 기록이라 실행하지 않고 원복 불가로 보고한다.
    _sqldir="$_dir/dbsql"
    if [ -d "$_sqldir" ]; then
        for _sqlfile in $(ls "$_sqldir" 2>/dev/null | sort -r); do
            _sql=$(cat "$_sqldir/$_sqlfile")
            case "$_sql" in
                --*) _rb_fail "SQL 원복 불가(기록만 있음): $(printf '%s' "$_sql" | head -n1)"; continue ;;
            esac
            _rc=0
            case "$_sqlfile" in
                *.mysql.sql) mysql_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
                *.postgres.sql) psql_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
                *.oracle.sql) oracle_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
            esac
            [ "$_rc" -eq 0 ] || _rb_fail "SQL 원복 실패: $(printf '%s' "$_sql" | head -n1)"
        done
    fi

    _baklist=$(find "$_dir" -type f 2>/dev/null)
    while IFS= read -r _bak; do
        [ -z "$_bak" ] && continue
        case "$_bak" in
            */dbsql/*|*/_services/*|"$_dir"/_oracle/*)
                # _oracle/ 은 oracle_pfile_backup 이 남긴 변경 전 SPFILE 사본(증적)이라 되돌릴 원래 경로가 없다 - 예전에는
                # "/_oracle/..." 로 복사하려다 실패해 D-19/D-26 Oracle 원복이 항상 "일부 실패"로 끝났다(1.4.0 D-C6).
                : # 따로 처리
                ;;
            *.WAS_ABSENT)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.WAS_ABSENT}"
                if [ -d "$_orig" ]; then rmdir "$_orig" 2>/dev/null || _rb_fail "조치가 만든 디렉터리를 지우지 못함(비어 있지 않음): $_orig"
                else rm -f "$_orig" || _rb_fail "조치가 만든 파일 삭제 실패: $_orig"; fi
                ;;
            *.OWNMETA)
                # fix_backup_owner 가 남긴 소유자·권한(파일·심볼릭 링크 공용). 링크는 링크 자체 소유자만 되돌린다.
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.OWNMETA}"
                if [ -e "$_orig" ] || [ -L "$_orig" ]; then
                    _owner=$(sed -n '1p' "$_bak")
                    _perm=$(sed -n '2p' "$_bak")
                    if ! chown -h "$_owner" "$_orig" 2>/dev/null || { [ ! -L "$_orig" ] && ! chmod "$_perm" "$_orig" 2>/dev/null; }; then
                        _rb_fail "소유자/권한 원복 실패: $_orig"
                    fi
                fi
                ;;
            *.DIRMETA)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.DIRMETA}"
                if [ -d "$_orig" ]; then
                    _owner=$(sed -n '1p' "$_bak")
                    _perm=$(sed -n '2p' "$_bak")
                    chown "$_owner" "$_orig" 2>/dev/null && chmod "$_perm" "$_orig" 2>/dev/null || _rb_fail "디렉터리 소유자/권한 원복 실패: $_orig"
                fi
                ;;
            *.TARBALL.tgz)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.TARBALL.tgz}"
                _origparent=$(dirname "$_orig")
                mkdir -p "$_origparent"
                (cd "$_origparent" 2>/dev/null && tar xzf "$_bak") || _rb_fail "삭제된 경로 복원 실패: $_orig"
                ;;
            *)
                _orig="/${_bak#"$_dir"/}"
                cp -p "$_bak" "$_orig" 2>/dev/null || _rb_fail "파일 원복 실패: $_orig"
                ;;
        esac
    done <<EOF
$_baklist
EOF

    # 서비스 상태는 설정 파일을 되돌린 뒤 마지막에 되살린다(fix_service_disable 가 기록)
    if [ -d "$_dir/_services" ] && command -v systemctl >/dev/null 2>&1; then
        for _sf in "$_dir/_services"/*; do
            [ -f "$_sf" ] || continue
            _unit=$(basename "$_sf")
            _was_enabled=$(sed -n '1p' "$_sf"); _was_active=$(sed -n '2p' "$_sf")
            [ "$_was_enabled" = "enabled" ] && { systemctl enable "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 enable 원복 실패: $_unit"; }
            [ "$_was_active" = "active" ] && { systemctl start "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 기동 원복 실패: $_unit"; }
            # U-C3(1.4.0): 조치가 켠 서비스(fix_service_enable - U-65/U-66)는 원래 꺼져 있었으면 다시 끈다
            [ "$_was_enabled" = "disabled" ] && { systemctl disable "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 disable 원복 실패: $_unit"; }
            [ -n "$_was_enabled" ] && case "$_was_active" in inactive|failed) systemctl stop "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 정지 원복 실패: $_unit" ;; esac
        done
    fi
}

# fix_set_owner_perm <파일> <소유자> <권한> — check_owner_perm 과 짝을 이루는 조치 헬퍼.
# 소유자는 인자로 받은 값 그대로(여러 후보 중 첫 번째를 호출부에서 선택해 전달), 권한은
# 정확히 그 값으로 설정한다(check_owner_perm 은 "이하"를 허용하지만 조치는 가이드 권고값으로 고정).
fix_set_owner_perm() {
    _f=$1; _owner=$2; _perm=$3
    if [ ! -e "$_f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$_f 파일이 존재하지 않음"; FIX_EVIDENCE=""
        return 1
    fi
    fix_backup "$_f"
    chown "$_owner" "$_f" 2>/dev/null
    chmod "$_perm" "$_f" 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$_f 소유자를 $_owner, 권한을 $_perm 로 설정함"
    FIX_EVIDENCE="$(ls -l "$_f" 2>/dev/null)"
}

# fix_service_disable <systemd 유닛...> — check_service_disabled 와 짝을 이루는 조치 헬퍼.
# 실행 중인 서비스를 정지(stop)하고 비활성화(disable)한다. 유닛이 하나라도 처리되면 0을 반환.
fix_service_disable() {
    _ok=0
    if command -v systemctl >/dev/null 2>&1; then
        for _u in "$@"; do
            # U-C4(1.4.0): list-unit-files 의 인자는 유닛 "파일 이름" 패턴이라 "snmpd" 는 snmpd.service 에 맞지 않는다(항상 실패 →
            # 건너뜀). 예전에는 그래서 서비스 조치(U-39/41/43/54/58 등)가 아무것도 끄지 못하고 재검증 VULN → 원복으로 끝났다
            # (systemd 가 없는 CI 에서는 드러나지 않음 - fixtures/cases 의 systemd 컨테이너로 발견). 종류가 없으면 .service 를 붙인다.
            case "$_u" in *.service|*.socket|*.target|*.timer|*.path|*.mount) ;; *) _u="$_u.service" ;; esac
            systemctl list-unit-files "$_u" >/dev/null 2>&1 || continue
            # 원복용으로 원래 상태(enabled/active)를 기록한다 - 예전에는 기록하지 않아 원복해도 서비스가 다시
            # 켜지지 않았다. 같은 항목에서 이미 기록했으면 첫 기록(조치 전 상태)을 유지한다.
            fix_service_record "$_u"
            systemctl stop "$_u" 2>/dev/null
            systemctl disable "$_u" 2>/dev/null && _ok=1
        done
    fi
    [ "$_ok" -eq 1 ] && return 0 || return 1
}

# fix_service_record <유닛> — 원복용으로 조치 전 상태(is-enabled / is-active 첫 줄)를 <백업>/<코드>/_services/<유닛> 에 남긴다.
# 같은 항목에서 이미 기록했으면 첫 기록(조치 전 상태)을 유지한다. 기록 실패는 변경 전 중단(F1).
fix_service_record() {
    _sd="$FIX_BACKUP_DIR/$FIX_CODE/_services"
    [ -f "$_sd/$1" ] && return 0
    mkdir -p "$_sd" 2>/dev/null || fix_abort_item "서비스 상태 백업 디렉터리 생성 실패: $_sd"
    { systemctl is-enabled "$1" 2>/dev/null | head -n1; systemctl is-active "$1" 2>/dev/null | head -n1; } > "$_sd/$1" \
        || fix_abort_item "서비스 상태 백업 실패: $1"
}

# fix_service_enable <유닛> — U-C3(1.4.0): 서비스를 켜는 조치(U-65 시각 동기화·U-66 로깅)용. 상태를 기록한 뒤
# enable --now 한다. 예전 조치는 기록 없이 켜서 --rollback 해도 서비스가 켜진 채로 남았다. 성공하면 0.
fix_service_enable() {
    fix_service_record "$1"
    systemctl enable --now "$1" >/dev/null 2>&1
}

# fix_xinetd_disable <xinetd.d 파일...> — "disable = no" 로 명시된 서비스를 "disable = yes" 로
# 강제한다(값이 아예 없는 파일은 배포판 기본값을 신뢰해 건드리지 않는다). 하나라도 바꾸면 xinetd를
# reload(가능한 경우)해 즉시 반영하고 0을 반환한다 — 일부 항목(U-38 등)은 check가 listening 포트
# 상태(ss/netstat)를 직접 확인하므로, 설정 파일만 고치고 reload 하지 않으면 재검증이 통과하지 않는다.
# sshd 등 관리 세션에 영향을 줄 수 있는 서비스는 절대 자동 재시작하지 않는다는 원칙과 달리,
# xinetd reload는 관리자 세션에 영향이 없어 안전하다.
fix_xinetd_disable() {
    _changed=0
    for _f in "$@"; do
        [ -f "$_f" ] || continue
        grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' "$_f" || continue
        fix_backup "$_f"
        fix_sed_inplace "$_f" -E 's/^([[:space:]]*disable[[:space:]]*=[[:space:]]*)no/\1yes/'
        _changed=1
    done
    if [ "$_changed" -eq 1 ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl try-reload-or-restart xinetd 2>/dev/null
        elif command -v service >/dev/null 2>&1; then
            service xinetd reload 2>/dev/null
        fi
        return 0
    fi
    return 1
}


# fix_rollback_all <fix-run-dir> — fix.sh --rollback 용: 해당 실행의 백업 전체를 원복한다.
# 여러 항목이 같은 파일을 순차적으로 수정한 경우, 원복은 적용의 역순(나중에 바뀐 항목부터)으로
# 처리해야 최종 상태가 "전부 적용 전"으로 정확히 돌아간다. 정순으로 처리하면 뒤에 적용된 항목의
# 백업(이미 앞 항목의 변경이 반영된 상태의 스냅샷)이 마지막에 덮어써 앞 항목의 조치만 남는 버그가
# 있었다(Web WEB-04/08/16/22가 같은 httpd.conf 를 순차 수정하는 실기 테스트로 실제로 발견 —
# 코드가 U-01~U-67 처럼 전부 2자리 zero-padding 이라 사전식 역순 정렬이 곧 적용 역순과 같다).
fix_rollback_all() {
    _run_dir=$1
    _backup_dir="$_run_dir/backup"
    if [ ! -d "$_backup_dir" ]; then
        log_error "$_backup_dir 를 찾을 수 없습니다."
        return 1
    fi
    # 다른 호스트에서 만든 백업을 이 호스트에 덮어쓰는 사고 방지(폴더 이름 규칙: <host>_<카테고리>_fix_<시각>)
    _rb_host=$(basename "$_run_dir" | sed 's/_[0-9][0-9]_fix_.*$//')
    _this_host=$(host_name)
    if [ "$_rb_host" != "$_this_host" ]; then
        log_warn "이 백업은 다른 호스트($_rb_host)에서 만든 것으로 보입니다(현재: $_this_host)."
        fix_confirm_tty "그래도 이 호스트에 원복하시겠습니까?" || { echo "원복하지 않았습니다."; return 1; }
    fi
    # 조치 이후 경과 시간이 길면 그 사이의 정상적인 설정 변경까지 되돌리게 된다 - 알리고 진행한다
    log_warn "원복은 조치 직전 상태로 덮어씁니다. 조치 이후에 사람이 바꾼 설정이 있으면 함께 되돌아갑니다."
    _codes=""
    for _code_dir in "$_backup_dir"/*/; do
        [ -d "$_code_dir" ] || continue
        _codes="$_codes
$(basename "$_code_dir")"
    done
    _codes=$(printf '%s\n' "$_codes" | grep -v '^$' | sort -r)
    FIX_ROLLBACK_FAILS=""
    for _code in $_codes; do
        _before_fails=$FIX_ROLLBACK_FAILS
        FIX_BACKUP_DIR="$_backup_dir" fix_rollback_item "$_code"
        if [ "$_before_fails" = "$FIX_ROLLBACK_FAILS" ]; then echo "원복 완료: $_code"; else echo "원복 일부 실패: $_code"; fi
    done
    if [ -n "$FIX_ROLLBACK_FAILS" ]; then
        log_error "되돌리지 못한 항목이 있습니다 - 수동 확인 필요:$FIX_ROLLBACK_FAILS"
        return 1
    fi
}

# ---- 조치 진입점 공통 흐름 (1.5.0 D2) ---------------------------------------------------------------
# 01_unix·03_web·08_dbms fix.sh 가 복붙하던 대상 선정·항목 루프·마무리를 한 곳에 둔다. 진입점은 옵션 해석·가드·
# 원복·결과 대상 확인(fix_check_result_target)·배너·엔진별 사전 검사만 남기고 아래 순서로 부른다:
#   fix_select_vuln_codes → fix_confirm_plan·fix_prepare_dir → (배너) → fix_items → fix_print_summary
# 진입점이 정해 두어야 하는 전역: GUIDE_JSON, RESULT_JSON, ITEM_FILTER, APPLY (fix_items 는 FIX_LOG 도 쓴다).

# fix_select_vuln_codes -- result.json 의 VULN 코드(-i 가 있으면 그중 지정한 것만)를 VULN_CODES·TOTAL 로. 없으면 exit 0.
fix_select_vuln_codes() {
    VULN_CODES=$(result_list_vuln_codes "$RESULT_JSON")
    if [ -n "$ITEM_FILTER" ]; then
        _fsv_wanted=" $(printf '%s' "$ITEM_FILTER" | tr ',' ' ') "
        _fsv_out=""
        for _fsv_c in $VULN_CODES; do
            case "$_fsv_wanted" in *" $_fsv_c "*) _fsv_out="$_fsv_out $_fsv_c" ;; esac
        done
        VULN_CODES=$(printf '%s' "$_fsv_out" | sed 's/^ //')
    fi
    if [ -z "$VULN_CODES" ]; then
        echo "적용 대상(취약 판정) 항목이 없습니다."
        exit 0
    fi
    TOTAL=$(echo "$VULN_CODES" | wc -w | tr -d ' ')
}

# fix_items <fix 폴더> <check 폴더> [조치 직후 함수] [재검증 직후 함수]
#   VULN_CODES 의 항목마다 등급(manual/auto/confirm)에 따라 안내·dry-run 미리보기·확인·적용(run_fix_isolated)·재검증·실패 시
#   원복을 하고 FIX_LOG 에 남긴다. 후처리 함수는 <코드> 를 인자로 받는다(예: 01 미검증 안내, 03 설정 문법 재검사).
#   FIX_STATUS 처리: SKIPPED = 조치로 해소할 수 없음(변경 없음, 재검증·원복 안 함, 01 U-01 등) / PARTIAL·MANUAL = 자동으로 바꿀 수
#   없는 부분이 남음(원복 안 함, 08 F-R6) / APPLIED·NA + 재검증이 VULN·ERROR 아님 = 성공 / 그 밖 = 실패 → 원복.
#   반환값 3(fix_abort_item, 백업 실패 등)이면 실행 전체를 exit 3 으로 끝낸다(F1).
fix_items() {
    _fi_fdir=$1; _fi_cdir=$2; _fi_postfix=${3:-}; _fi_postcheck=${4:-}
    N_APPLIED=0; N_SKIPPED=0; N_DECLINED=0; N_FAILED=0; N_MANUAL=0; N_PREVIEW=0; N_PARTIAL=0; N_POLICY_SKIPPED=0
    FAILED_CODES=""
    for _fi_code in $VULN_CODES; do
        _fi_title=$(guide_field "$GUIDE_JSON" "$_fi_code" "title")
        _fi_grade=$(guide_field "$GUIDE_JSON" "$_fi_code" "fix")
        [ -z "$_fi_grade" ] && _fi_grade="manual"

        # 1.6.0 G-01: 정책 모드면 승인(·호스트 제외 아님)된 항목만 다룬다 - 나머지는 POLICY_SKIPPED(dry-run 도 같은 판정을 미리 보여 줌)
        if ! fix_policy_approved "$_fi_code"; then
            _fi_policy_skip "$_fi_code" "$_fi_title" "$_fi_grade"
            continue
        fi

        if [ "$_fi_grade" = "manual" ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  등급: manual (자동 조치 없음) — 가이드 조치 방법: $(guide_field "$GUIDE_JSON" "$_fi_code" "remediation")"
            printf '%s\t%s\tMANUAL\t%s\n' "$_fi_code" "manual" "자동 조치 없음(가이드 조치 방법 안내만)" | fix_log_stamp >> "$FIX_LOG"
            N_MANUAL=$((N_MANUAL + 1))
            continue
        fi

        _fi_fix="$_fi_fdir/$_fi_code.sh"
        _fi_check="$_fi_cdir/$_fi_code.sh"

        if [ ! -f "$_fi_fix" ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  등급: $_fi_grade 이나 조치 스크립트 미구현(또는 이 환경 대상 아님) — 건너뜀"
            printf '%s\t%s\tSKIPPED\t조치 스크립트 미구현\n' "$_fi_code" "$_fi_grade" | fix_log_stamp >> "$FIX_LOG"
            N_SKIPPED=$((N_SKIPPED + 1))
            continue
        fi

        # G-02: 원복 불가(# 원복:)·업무 중단 가능(# 영향:) 조치는 정책에 코드:irreversible 이 있어야 한다
        if ! fix_policy_irrev_ok "$_fi_code" "$_fi_fix"; then
            _fi_policy_skip "$_fi_code" "$_fi_title" "$_fi_grade"
            continue
        fi

        if [ "$APPLY" -ne 1 ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  등급: $_fi_grade (dry-run — 실제 적용하려면 --apply 추가)"
            if [ "$POLICY_SET" -eq 1 ]; then
                case "$POLICY_IRREV" in *" $_fi_code "*) echo "  정책: 적용 예정(승인됨, irreversible)" ;; *) echo "  정책: 적용 예정(승인됨)" ;; esac
            fi
            _fi_chg=$(fix_change_note "$_fi_fix"); [ -n "$_fi_chg" ] && echo "  변경: $_fi_chg"
            _fi_rbn=$(fix_rollback_note "$_fi_fix"); [ -n "$_fi_rbn" ] && echo "  원복: $_fi_rbn"
            _fi_imp=$(fix_impact_note "$_fi_fix"); [ -n "$_fi_imp" ] && echo "  영향: $_fi_imp"
            N_PREVIEW=$((N_PREVIEW + 1))
            continue
        fi

        # 정책 모드: confirm 등급의 항목별 y/N 은 정책 승인으로 대신한다(비밀번호 직접 입력처럼 터미널이 필요한 조치는 조치 안에서 그대로 건너뜀)
        if [ "$_fi_grade" = "confirm" ] && [ "$POLICY_SET" -eq 1 ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  등급: confirm — 정책 승인으로 항목별 확인 생략(승인자 $POLICY_APPROVER)"
        elif [ "$_fi_grade" = "confirm" ]; then
            printf '[%s] %s\n  등급: confirm — 실제로 적용하시겠습니까? [y/N] ' "$_fi_code" "$_fi_title"
            # /dev/tty 가 있어도 제어 터미널이 없는 비대화형 실행(docker exec 파이프, 크론)에서는 읽기가 실패한다 - 실패는
            # 흡수하고 항상 안전한 기본값(미확인)으로 처리한다(set -u 에서 _fi_ans 미할당으로 죽던 문제 포함).
            _fi_ans=""
            read -r _fi_ans < /dev/tty 2>/dev/null || _fi_ans=""
            case "$_fi_ans" in
                y|Y) : ;;
                *)
                    echo "  건너뜀 (사용자 미확인)"
                    printf '%s\t%s\tDECLINED\t사용자가 확인하지 않음\n' "$_fi_code" "$_fi_grade" | fix_log_stamp >> "$FIX_LOG"
                    N_DECLINED=$((N_DECLINED + 1))
                    continue
                    ;;
            esac
        fi

        FIX_CODE="$_fi_code"
        export FIX_CODE
        # X-04(1.3.4): 조치는 서브셸에서 실행한다(run_fix_isolated) - 중간에 죽어도 FIX_STATUS=ERROR 로 돌아와 아래 실패 경로가
        # 원복·FAILED_* 기록 후 다음 항목으로 간다. 3 = fix_abort_item: 서브셸이 이미 원복·ABORTED 기록 → 실행 전체 중단(F1).
        _fi_rc=0; run_fix_isolated "$_fi_fix" || _fi_rc=$?
        if [ "$_fi_rc" -eq 3 ]; then fix_audit_finish "fix_abort_item($_fi_code)"; exit 3; fi
        if [ -n "$_fi_postfix" ]; then "$_fi_postfix" "$_fi_code"; fi

        if [ "$FIX_STATUS" = "SKIPPED" ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  건너뜀(변경 없음) — $FIX_DETAIL"
            printf '%s\t%s\tSKIPPED\t%s\n' "$_fi_code" "$_fi_grade" "$FIX_DETAIL" | fix_log_stamp >> "$FIX_LOG"
            N_SKIPPED=$((N_SKIPPED + 1))
            unset FIX_CODE
            continue
        fi

        CHECK_STATUS="ERROR"; CHECK_DETAIL="check 스크립트 없음"; CHECK_EVIDENCE=""
        if [ -f "$_fi_check" ]; then
            run_check_isolated "$_fi_check"
        fi
        if [ -n "$_fi_postcheck" ]; then "$_fi_postcheck" "$_fi_code"; fi

        # 성공 기준은 "재검증이 VULN/ERROR 를 벗어났는가"다 - U-66 처럼 조직 정책 대조가 필요해 MANUAL 까지만 가는 항목이 있어
        # GOOD 만 인정하면 정상 조치도 항상 원복된다. FIX_STATUS=NA 는 "이미 대상이 없어 조치 불필요"라 성공으로 본다.
        if [ "$FIX_STATUS" = "PARTIAL" ] || [ "$FIX_STATUS" = "MANUAL" ]; then
            echo "[$_fi_code] $_fi_title"
            if [ "$FIX_STATUS" = "PARTIAL" ]; then
                echo "  일부 적용 — 남은 부분은 수동 조치 필요(재검증: $CHECK_STATUS, 원복하지 않음): $FIX_DETAIL"
                _fi_fs="PARTIAL_MANUAL"; N_PARTIAL=$((N_PARTIAL + 1))
            else
                echo "  자동 조치 불가 — 수동 조치 필요(변경 없음, 재검증: $CHECK_STATUS): $FIX_DETAIL"
                _fi_fs="MANUAL"; N_MANUAL=$((N_MANUAL + 1))
            fi
            printf '%s\t%s\t%s\t%s (recheck=%s)\n' "$_fi_code" "$_fi_grade" "$_fi_fs" "$FIX_DETAIL" "$CHECK_STATUS" | fix_log_stamp >> "$FIX_LOG"
        elif { [ "$FIX_STATUS" = "APPLIED" ] || [ "$FIX_STATUS" = "NA" ]; } && [ "$CHECK_STATUS" != "VULN" ] && [ "$CHECK_STATUS" != "ERROR" ]; then
            echo "[$_fi_code] $_fi_title"
            echo "  적용 완료 — 재검증 결과: $CHECK_STATUS ($FIX_DETAIL)"
            printf '%s\t%s\tAPPLIED\t%s (recheck=%s)\n' "$_fi_code" "$_fi_grade" "$FIX_DETAIL" "$CHECK_STATUS" | fix_log_stamp >> "$FIX_LOG"
            N_APPLIED=$((N_APPLIED + 1))
        else
            echo "[$_fi_code] $_fi_title"
            echo "  적용 실패 또는 재검증 실패(FIX_STATUS=$FIX_STATUS, 재검증=$CHECK_STATUS) — 원복 중"
            # 되돌리지 못한 부분이 있으면 FAILED_NOT_ROLLED_BACK 으로 정직하게 남긴다(FIX_ROLLBACK_FAILS)
            FIX_ROLLBACK_FAILS=""
            fix_rollback_item "$_fi_code"
            if [ -z "$FIX_ROLLBACK_FAILS" ]; then _fi_rbs="FAILED_ROLLED_BACK"; else _fi_rbs="FAILED_NOT_ROLLED_BACK"; echo "  원복하지 못한 부분(수동 확인 필요):$FIX_ROLLBACK_FAILS"; fi
            printf '%s\t%s\t%s\tFIX_STATUS=%s detail=%s recheck=%s %s\n' "$_fi_code" "$_fi_grade" "$_fi_rbs" "$FIX_STATUS" "$FIX_DETAIL" "$CHECK_STATUS" "$(printf '%s' "$FIX_ROLLBACK_FAILS" | tr '\n' ' ')" | fix_log_stamp >> "$FIX_LOG"
            N_FAILED=$((N_FAILED + 1)); FAILED_CODES="$FAILED_CODES $_fi_code"
        fi
        unset FIX_CODE
    done
}

# _fi_policy_skip <코드> <제목> <등급> — 정책으로 건너뛴 항목 기록(POLICY_REASON 을 사유로)
_fi_policy_skip() {
    echo "[$1] $2"
    echo "  정책으로 건너뜀(변경 없음) — $POLICY_REASON"
    printf '%s\t%s\tPOLICY_SKIPPED\t%s\n' "$1" "$3" "$POLICY_REASON" | fix_log_stamp >> "$FIX_LOG"
    N_POLICY_SKIPPED=$((N_POLICY_SKIPPED + 1))
}

# fix_print_summary <원복 명령> -- 건수·백업 위치·원복 방법·로그 경로 출력
fix_print_summary() {
    echo "------------------------------------------------------------------------"
    if [ "$APPLY" -eq 1 ]; then
        echo "적용 완료: $N_APPLIED, 일부 적용(남은 부분 수동): $N_PARTIAL, 실패(원복됨): $N_FAILED, 확인거부: $N_DECLINED, 건너뜀(스크립트없음·조치로 해소 불가): $N_SKIPPED, 수동조치: $N_MANUAL"
        # 1.6.0 G-01: 무인 실행에서도 실패 항목을 놓치지 않게 코드 목록을 따로 보여 준다
        [ -n "${FAILED_CODES:-}" ] && echo "실패 항목: $(printf '%s' "$FAILED_CODES" | sed 's/^ //; s/ /, /g') (원복 결과는 로그 참고)"
        echo "백업 위치: $FIX_BACKUP_DIR"
        echo "원복하려면: $1 --rollback $FIX_OUT_DIR"
    else
        echo "DRY-RUN 미리보기: $N_PREVIEW 건 (--apply 로 실제 적용), 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
    fi
    if [ "$POLICY_SET" -eq 1 ]; then
        echo "정책으로 건너뜀(미승인·호스트 제외·irreversible 플래그 없음): ${N_POLICY_SKIPPED:-0}건"
        echo "감사 기록: $AUDIT_FILE"
        fix_audit_finish
    fi
    echo "로그: $FIX_LOG"
}

# U-32 (중) 홈 디렉토리로 지정한 디렉토리의 존재 관리 — 조치
# 가이드 조치 방법: 홈 디렉토리가 존재하지 않는 계정에 홈 디렉토리 설정(또는 불필요 계정 삭제 - 자동화 대상 아님)
# 대상 계정은 진단(checks/U-32.sh)과 같은 기준으로 고른다(F-R9). 예전 조치는 nologin/false 계정을 모두 건너뛰었는데
# 진단은 가이드 판단기준("홈 디렉토리가 존재하지 않는 계정")대로 nologin 계정도 보므로, Debian 기본 시스템 계정
# (list → /var/list, irc → /run/ircd 등) 때문에 재검증이 항상 VULN → 원복으로 끝났다.
#  - 로그인 가능한 계정: 계정 소유(uid:주 gid), 750 (가이드 예시 /home/<user>)
#  - nologin/false 시스템 계정: root:root, 755 - 로그인하지 않는 서비스 계정에 새로 쓰기 가능한 공간을 주지 않는다
#    (예: www-data 의 /var/www 를 www-data 소유로 만들면 웹 서버 계정이 웹 루트에 쓸 수 있게 됨).
#  - 상위 디렉터리가 없으면 만들지 않는다(mkdir -p 로 만든 상위 경로는 원복 시 지워지지 않으므로).
#  - 원격/자동마운트 위 경로는 진단처럼 건드리지 않는다.
run_fix() {
    passwd_file="/etc/passwd"
    applied=""; volatile=""; failed=""
    while IFS=: read -r name _ uid gid _ home shell; do
        [ -z "$name" ] && continue
        case "$home" in
            /|/nonexistent|/nonexisting) continue ;;
        esac
        sysacct=0
        case "$shell" in
            */nologin|*/false) sysacct=1; [ "$home" = "" ] && continue ;;
        esac
        [ -z "$home" ] && { failed="$failed $name(홈 경로 비어 있음)"; continue; }
        if is_remote_or_auto_fs "$home"; then continue; fi
        [ -d "$home" ] && continue
        if [ -e "$home" ] || [ -L "$home" ]; then failed="$failed $home($name, 디렉터리가 아닌 파일이 있음)"; continue; fi
        if [ ! -d "$(dirname "$home")" ]; then failed="$failed $home($name, 상위 디렉터리 없음)"; continue; fi
        # 새로 만들 디렉터리이므로 원복 시 삭제되도록 먼저 WAS_ABSENT 마커를 남긴다
        fix_backup "$home"
        if [ "$sysacct" -eq 1 ]; then own="0:0"; mode=755; else own="$uid:$gid"; mode=750; fi
        if ! mkdir "$home" 2>/dev/null || ! chown "$own" "$home" 2>/dev/null || ! chmod "$mode" "$home" 2>/dev/null; then
            failed="$failed $home($name, 생성/소유자 설정 실패)"; continue
        fi
        applied="$applied $home($name,$mode$( [ "$sysacct" -eq 1 ] && printf ',root 소유'))"
        case "$home" in /run/*|/var/run/*|/tmp/*) volatile="$volatile $home" ;; esac
    done < "$passwd_file"

    note=""
    [ -n "$volatile" ] && note=" / 주의: 임시 파일시스템 경로라 재부팅 시 사라짐(서비스가 기동 시 만들거나 tmpfiles.d 등록 필요):$volatile"
    [ -n "$failed" ] && note="$note / 만들지 못함(계정 삭제 또는 /etc/passwd 홈 경로 수정 등 수동 조치 필요):$failed"
    if [ -z "$applied" ] && [ -z "$failed" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="홈 디렉토리가 없는 계정이 없어 조치 불필요"; FIX_EVIDENCE=""
    elif [ -z "$applied" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="홈 디렉토리를 만들지 않음$note"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="홈 디렉토리를 새로 생성함(로그인 계정은 계정 소유 750, nologin 시스템 계정은 root 소유 755):$applied$note"; FIX_EVIDENCE="$applied"
    fi
}

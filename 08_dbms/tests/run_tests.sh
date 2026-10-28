#!/bin/sh
# 08_dbms/tests/run_tests.sh — Docker(공식 mysql:8/postgres:16) 기반 회귀 테스트.
# 저장소 루트에서 실행: sh 08_dbms/tests/run_tests.sh
#
# 01_unix/03_web과 달리 DB 서버와 run.sh를 실행하는 쪽이 분리되어 있어(원격 접속 모델)
# 매 (엔진,모드) 조합마다: ①전용 docker 네트워크 생성 ②DB 서버 컨테이너 기동 ③클라이언트
# 컨테이너에서 fixtures/setup.sh 적용 후 run.sh 실행 ④docker cp로 결과 추출 ⑤컨테이너/네트워크
# 정리, 순서로 진행한다. Oracle은 이미지가 무거워 여기 포함하지 않았다(CI의 별도 주간
# job 후보 - 08_dbms/CLAUDE.md "테스트 커버리지" 참고). D-11(시스템 테이블 접근 제한)만
# 명시적으로 vuln/hardened를 가르고 나머지 25항목은 각 이미지의 기본값을 반영한다(run.sh는
# 매번 26항목 전체를 돌려 다른 항목의 회귀도 함께 잡아낸다). "원격 클라이언트 컨테이너에서
# run.sh 실행" 토폴로지라 로컬 파일·프로세스 기반 항목(MySQL D-07/D-14, PostgreSQL D-10/D-14)은
# 원격 모드 MANUAL 로 나와야 한다(진단 검수 D-R1 - 예전에는 클라이언트 컨테이너의 /etc/my.cnf 로
# D-14 를 판정했다). vuln 모드에서는 권한 없는 계정(lowpriv)으로 한 번 더 진단해 권한 부족 항목이
# GOOD/VULN 대신 ERROR 인지 확인한다(D-R2).
set -eu
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/../.."

# 테스트 산출물(조치·운영 안전 검사 작업 파일)은 저장소 루트가 아니라 이 임시 폴더에 두고 끝나면 지운다.
# docker cp 대상이 Windows(Git Bash)에서도 풀리도록 상대 경로를 쓴다 - 08_dbms/tests 아래 숨김 폴더.
TMPW="08_dbms/tests/.tmp_run_$$"
mkdir -p "$TMPW"
trap 'rm -f "$TMPW"/dbsafety_* "$TMPW"/fix_*.out 2>/dev/null; rmdir "$TMPW" 2>/dev/null' EXIT
trap 'exit 130' INT TERM

fail=0
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    echo "[빌드] $engine 클라이언트 이미지..."
    docker build -q -f "08_dbms/tests/Dockerfile.$engine" -t "$image" . >/dev/null

    for mode in vuln hardened; do
        echo "[*] $engine/$mode 픽스처 실행..."
        net="kisa-dbms-net-$$-$engine-$mode"
        docker network create "$net" >/dev/null

        if [ "$engine" = "mysql" ]; then
            db_cid=$(docker run -d --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8)
        else
            db_cid=$(docker run -d --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16)
        fi

        # DB 가 접속을 받을 때까지 대기(최대 60초)
        ready=0
        i=0
        while [ "$i" -lt 30 ]; do
            if [ "$engine" = "mysql" ]; then
                docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
            else
                docker run --rm --network "$net" -e PGPASSWORD=TestRoot123! "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
            fi
            i=$((i + 1))
            sleep 2
        done

        if [ "$ready" -ne 1 ]; then
            echo "FAIL: $engine/$mode - DB 서버가 60초 내에 준비되지 않음"
            fail=1
        else
            if [ "$engine" = "mysql" ]; then dbuser="root"; else dbuser="postgres"; fi
            cid=$(docker create --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c "
                sh 08_dbms/tests/fixtures/setup.sh $engine $mode >/dev/null 2>&1
                sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1
                cp /tmp/out/*/result.json /result.json
                if [ $mode = vuln ]; then
                    DB_PASSWORD='LowPriv123!' sh 08_dbms/run.sh -e $engine --host dbhost --user lowpriv -o /tmp/out_low >/dev/null 2>&1
                    cp /tmp/out_low/*/result.json /result_lowpriv.json
                fi
            ")
            docker start -a "$cid" >/dev/null
            result_file="result_${engine}_${mode}.json"
            docker cp "$cid:/result.json" "$result_file" >/dev/null 2>&1
            low_file="result_${engine}_lowpriv.json"
            [ "$mode" = "vuln" ] && docker cp "$cid:/result_lowpriv.json" "$low_file" >/dev/null 2>&1
            docker rm "$cid" >/dev/null

            # 권한 없는 계정 진단: 전체를 볼 수 없는 항목은 GOOD/VULN 이 아니라 ERROR 여야 한다(진단 검수 D-R2)
            if [ "$mode" = "vuln" ]; then
                if [ ! -f "$low_file" ]; then
                    echo "FAIL: $engine/lowpriv - 권한 없는 계정 진단 결과를 꺼내지 못함"; fail=1
                elif python3 - "$low_file" "$result_file" "$engine/lowpriv" <<'PYEOF'
# 권한 없는 계정 결과를 같은 상태(vuln 픽스처)의 관리자 계정 결과와 전 항목 비교한다(S6 - 확인 못 한 것을 양호로 판정 금지).
# 관리자 결과보다 "좋게" 나오면 실패: 관리자 ≠ GOOD 인데 GOOD, 관리자 ≠ NA 인데 NA, 관리자 VULN 인데 VULN/ERROR 가 아님.
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
path, root_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
st = {it["code"]: (it["status"], it["detail"]) for it in json.load(open(path, encoding="utf-8"))["items"]}
root = {it["code"]: it["status"] for it in json.load(open(root_path, encoding="utf-8"))["items"]}
fails = []
must_error = ["D-01", "D-08", "D-11"]
fails += [f"{c}: 권한 부족 항목이 ERROR 가 아님 - {st.get(c)}" for c in must_error if st.get(c, ("?", ""))[0] != "ERROR"]
if set(st) != set(root):
    fails.append(f"항목 집합이 관리자 결과와 다름: 누락 {sorted(set(root) - set(st))} 추가 {sorted(set(st) - set(root))}")
for c, r in sorted(root.items()):
    low = st.get(c, ("?", ""))[0]
    if (low == "GOOD" and r != "GOOD") or (low == "NA" and r != "NA") or (r == "VULN" and low not in ("VULN", "ERROR")):
        fails.append(f"{c}: 관리자={r} 권한 없는 계정={low} ({st.get(c, ('', ''))[1][:120]})")
if fails:
    print(f"FAIL: {label} - 권한 없는 계정이 관리자보다 좋은 판정(거짓 양호)")
    for f in fails:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: {label} ({', '.join(must_error)} = ERROR, 전 {len(root)}항목 관리자 결과 대비 거짓 양호 없음)")
PYEOF
                then :; else fail=1; fi
                rm -f "$low_file"
            fi

            if [ ! -f "$result_file" ]; then
                echo "FAIL: $engine/$mode - 컨테이너에서 result.json 을 꺼내지 못함"
                fail=1
            elif python3 - "$result_file" "08_dbms/tests/fixtures/expected_${engine}_${mode}.json" "$engine/$mode" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
result_path, expected_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
actual = {it["code"]: it["status"] for it in json.load(open(result_path, encoding="utf-8"))["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
if failures:
    print(f"FAIL: {label} - {len(failures)}건 불일치")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: {label}")
PYEOF
            then :; else fail=1; fi
            rm -f "$result_file"
        fi

        docker rm -f "$db_cid" >/dev/null 2>&1 || true
        docker network rm "$net" >/dev/null 2>&1 || true
    done
done

# ---- 운영 안전 회귀 테스트 ---------------------------------------------------------
# ① 잘못된 비밀번호로 run.sh 를 돌려도 DB 서버가 본 로그인 실패는 정확히 1회여야 한다(항목마다
#    재시도하면 Oracle FAILED_LOGIN_ATTEMPTS 등으로 운영 계정이 잠김 - lib/common.sh db_preflight).
# ② 이때 DB 조회 항목은 "사전 점검 실패" 사유의 ERROR 로 남아야 한다(거짓 GOOD/VULN 금지).
# ③ 비밀번호 없이 실행해도 프롬프트에서 멈추지 않고 끝나야 한다(psql -w, _db_run).
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    net="kisa-dbms-net-$$-$engine-safety"
    docker network create "$net" >/dev/null
    if [ "$engine" = "mysql" ]; then
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8)
        dbuser="root"
    else
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16)
        dbuser="postgres"
    fi
    ready=0; i=0
    while [ "$i" -lt 30 ]; do
        if [ "$engine" = "mysql" ]; then
            docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
        else
            docker run --rm --network "$net" "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
        fi
        i=$((i + 1)); sleep 2
    done
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: $engine/safety - DB 서버가 60초 내에 준비되지 않음"; fail=1
    else
        mysql_aborted() {
            docker run --rm --network "$net" "$image" sh -c \
                "mysql -h dbhost -uroot -pTestRoot123! -N -B -e \"SHOW GLOBAL STATUS LIKE 'Aborted_connects'\" 2>/dev/null" | awk '{print $2}'
        }
        before=0
        [ "$engine" = "mysql" ] && before=$(mysql_aborted)
        [ "$engine" = "postgres" ] && before=$(docker logs "$db_cid" 2>&1 | grep -c 'password authentication failed' || true)

        safety_json="result_${engine}_safety.json"
        rc=0
        docker run --rm --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD='WrongPass!9' "$image" sh -c "
            timeout 300 sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1
            echo \"rc=\$?\" >&2
            cat /tmp/out/*/result.json" > "$safety_json" 2>"$safety_json.rc" || rc=$?

        if [ "$engine" = "mysql" ]; then
            after=$(mysql_aborted)
        else
            after=$(docker logs "$db_cid" 2>&1 | grep -c 'password authentication failed' || true)
        fi
        attempts=$((after - before))
        run_rc=$(sed -n 's/^rc=//p' "$safety_json.rc")

        nopw_rc=$(docker run --rm --network "$net" -e DB_HOST=dbhost "$image" sh -c "
            timeout 300 sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1; echo \$?" || true)

        if [ "$attempts" -ne 1 ]; then
            echo "FAIL: $engine/safety - 잘못된 비밀번호로 로그인 실패 ${attempts}회 발생(기대 1회)"; fail=1
        elif [ "$run_rc" = "124" ] || [ "$nopw_rc" = "124" ]; then
            echo "FAIL: $engine/safety - run.sh 가 300초 안에 끝나지 않음(대기/프롬프트 의심)"; fail=1
        elif python3 - "$safety_json" "$engine/safety" "$engine" <<'PYEOF'
# 접속 실패 시 DB 를 조회해야 하는 항목은 GOOD/VULN/NA 가 될 수 없다(S6). DB 를 조회하지 않는 항목(파일·프로세스 기반 -
# checks/<엔진> 에서 *_query/db_exec 를 쓰지 않는 파일)만 허용하고, 엔진 폴더에 check 가 없는 항목의 NA(대상 아님)는 정상.
import json, os, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
path, label, engine = sys.argv[1], sys.argv[2], sys.argv[3]
NO_DB = {"mysql": {"D-07", "D-14"}, "postgres": {"D-10", "D-14"}}[engine]
items = json.load(open(path, encoding="utf-8"))["items"]
blocked = [it for it in items if it["status"] == "ERROR" and "사전 점검 실패" in it["detail"]]
judged = [it["code"] for it in items if it["status"] in ("GOOD", "VULN") and "사전 점검" not in it["detail"]]
bad = [f"{it['code']}={it['status']} ({it['detail'][:100]})" for it in items
       if it["code"] not in NO_DB and os.path.exists(f"08_dbms/checks/{engine}/{it['code']}.sh")
       and it["status"] in ("GOOD", "VULN", "NA")]
if not blocked:
    print(f"FAIL: {label} - '사전 점검 실패' ERROR 항목이 없음"); sys.exit(1)
if bad:
    print(f"FAIL: {label} - 접속 실패인데 DB 조회 항목이 판정됨(거짓 판정)")
    for b in bad:
        print(f"  - {b}")
    sys.exit(1)
print(f"PASS: {label} (로그인 실패 1회, 차단된 DB 조회 항목 {len(blocked)}개, 접속 없이 판정된 항목 {judged} ⊆ 허용 {sorted(NO_DB)})")
PYEOF
        then :; else fail=1; fi
        rm -f "$safety_json" "$safety_json.rc"
    fi
    docker rm -f "$db_cid" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
done

# ---- 진단 운영 안전 실기 검사(lib/tests/run_safety.sh) + DB 서버 상태·쿼리 로그 (운영 안전 기준 S1/S2/S5/S6) --------
# vuln 픽스처를 적용한 DB 서버를 대상으로 클라이언트 컨테이너에서 lib/tests/run_safety.sh 를 돌린다(관리자 OS 계정·일반 OS
# 계정으로 각각 run.sh 실행, 클라이언트 쪽 파일·/tmp·프로세스 전후 비교, 출력물 권한, 비밀값 미노출). 그와 별도로
#  ① DB 서버 상태 스냅샷(MySQL: SHOW GLOBAL VARIABLES·계정·권한 테이블 / PostgreSQL: pg_settings·pg_roles·pg_authid 해시·
#     pg_hba_file_rules·DB ACL·role 설정)을 진단 전후로 떠서 같아야 한다(서버는 다른 컨테이너라 run_safety 가 못 본다).
#  ② DB 서버가 실제로 받은 문장(MySQL general_log 를 HEX 로 꺼냄 / PostgreSQL csvlog - 여러 줄 문장도 한 레코드)이 모두
#     읽기 전용인지 run_safety_check.py 의 sql_is_readonly 로 확인한다. 테스트 자신이 보낸 문장은 정확히 일치할 때만 뺀다.
# 원격 DB 진단은 OS 권한과 무관하므로(DB 계정 권한으로 판정) 일반 OS 계정 실행 결과는 관리자 실행 결과와 항목별로 같아야
# 한다 - run_safety_check.py 의 "일반 사용자 실행에 GOOD/NA 가 남음"(OS 파일·프로세스를 읽는 카테고리용 규칙)만 이 비교로 대신한다.
DB_SECRETS='TestRoot123!|LowPriv123!'
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    net="kisa-db-safety-net-$$-$engine"
    srv="kisa-db-safety-srv-$$-$engine"
    cli="kisa-db-safety-cli-$$-$engine"
    docker network create "$net" >/dev/null
    if [ "$engine" = "mysql" ]; then
        docker run -d --name "$srv" --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8 >/dev/null; dbuser="root"
    else
        docker run -d --name "$srv" --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16 \
            -c logging_collector=on -c log_destination=csvlog -c log_directory=/tmp/kisa_pglog -c log_filename=pg.log \
            -c log_statement=all >/dev/null; dbuser="postgres"
    fi
    ready=0; i=0
    while [ "$i" -lt 30 ]; do
        if [ "$engine" = "mysql" ]; then
            docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
        else
            docker run --rm --network "$net" "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
        fi
        i=$((i + 1)); sleep 2
    done
    work="$TMPW/dbsafety_${engine}_"
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: $engine/run-safety - DB 서버가 60초 내에 준비되지 않음"; fail=1
    else
        if [ "$engine" = "mysql" ]; then
            snap='mysql -h dbhost -uroot -N -B -e "SHOW GLOBAL VARIABLES WHERE Variable_name NOT IN ('"'"'gtid_executed'"'"','"'"'gtid_purged'"'"','"'"'log_output'"'"','"'"'general_log'"'"');
                SELECT user, host, plugin, account_locked, password_expired, password_last_changed, SHA2(authentication_string, 256) FROM mysql.user ORDER BY user, host;
                SELECT * FROM mysql.db ORDER BY user, host, db; SELECT * FROM mysql.tables_priv ORDER BY user, host, db, table_name;
                SELECT * FROM mysql.columns_priv ORDER BY user, host, db, table_name, column_name; SELECT * FROM mysql.role_edges;
                SELECT * FROM mysql.global_grants ORDER BY user, host, priv; SHOW DATABASES;"'
            on='mysql -h dbhost -uroot -e "SET GLOBAL log_output='"'"'TABLE'"'"'; TRUNCATE mysql.general_log; SET GLOBAL general_log='"'"'ON'"'"';"'
            off='mysql -h dbhost -uroot -N -B -e "SET GLOBAL general_log='"'"'OFF'"'"'; SELECT HEX(argument) FROM mysql.general_log WHERE command_type IN ('"'"'Query'"'"','"'"'Execute'"'"');" > /sql.log'
            env_pw="MYSQL_PWD"
        else
            snap='psql -h dbhost -U postgres -qAtX -c "SELECT name, setting, source FROM pg_settings ORDER BY name" -c "SELECT * FROM pg_roles ORDER BY rolname" \
                -c "SELECT rolname, md5(coalesce(rolpassword, '"'"''"'"')) FROM pg_authid ORDER BY rolname" -c "SELECT * FROM pg_hba_file_rules" \
                -c "SELECT datname, datacl, datallowconn FROM pg_database ORDER BY datname" -c "SELECT * FROM pg_db_role_setting" \
                -c "SELECT nspname, nspacl FROM pg_namespace ORDER BY nspname"'
            on='psql -h dbhost -U postgres -qAtX -c "SELECT '"'"'kisa_sql_begin'"'"'" >/dev/null'
            off='psql -h dbhost -U postgres -qAtX -c "SELECT '"'"'kisa_sql_end'"'"'" >/dev/null'
            env_pw="PGPASSWORD"
        fi
        docker run --name "$cli" --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c "
            sh 08_dbms/tests/fixtures/setup.sh $engine vuln >/dev/null 2>&1
            ( export $env_pw=\"\$DB_PASSWORD\"; $snap ) > /snap0 2>&1
            ( export $env_pw=\"\$DB_PASSWORD\"; $on ) 2>/dev/null
            RUN_CMD='sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser' SECRETS='$DB_SECRETS' sh lib/tests/run_safety.sh
            ( export $env_pw=\"\$DB_PASSWORD\"; $off ) 2>/dev/null
            ( export $env_pw=\"\$DB_PASSWORD\"; $snap ) > /snap1 2>&1
            true" >/dev/null 2>&1 || true
        # /rs 는 디렉터리 대신 tar 로 받아 python 임시 폴더에 풀어 판정한다(저장소에 폴더를 만들지 않음)
        docker cp "$cli:/rs" - > "${work}rs.tar" 2>/dev/null
        docker cp "$cli:/snap0" - > "${work}snap0.tar" 2>/dev/null
        docker cp "$cli:/snap1" - > "${work}snap1.tar" 2>/dev/null
        if [ "$engine" = "mysql" ]; then
            docker cp "$cli:/sql.log" - > "${work}sql.tar" 2>/dev/null
        else
            docker exec "$srv" cat /tmp/kisa_pglog/pg.csv > "${work}sql.log" 2>/dev/null
        fi
        docker rm -f "$cli" >/dev/null 2>&1 || true

        python3 - "$work" "$engine" <<'PYEOF' || fail=1
import csv, io, json, os, re, subprocess, sys, tarfile, tempfile
sys.path.insert(0, "lib/tests")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
from run_safety_check import sql_is_readonly, _sql_strip
prefix, engine = sys.argv[1], sys.argv[2]
label = f"dbms/{engine}/run-safety"
fails, notes = [], []
tmp = tempfile.TemporaryDirectory()
work = tmp.name
for name in ("rs", "snap0", "snap1", "sql"):
    p = f"{prefix}{name}.tar"
    if os.path.exists(p) and os.path.getsize(p):
        with tarfile.open(p) as t:
            t.extractall(work)
if os.path.exists(prefix + "sql.log"):
    with open(prefix + "sql.log", "rb") as src, open(os.path.join(work, "sql.log"), "wb") as dst:
        dst.write(src.read())

def read(p):
    try:
        return open(os.path.join(work, p), encoding="utf-8", errors="replace").read()
    except OSError:
        return None

# ① run_safety_check.py - "일반 사용자 실행에 GOOD/NA 금지"(OS 파일·프로세스를 읽는 카테고리용 규칙) 대신 --nr-same
#    (관리자·일반 OS 계정 결과 항목별 동일)으로 판정한다. 아래 ②는 항목 집합 차이까지 보는 보조 확인.
# --allow-fs: 일반 OS 계정 실행 때 run_safety.sh 의 su 가 남기는 로그인 기록(/var/log/lastlog, Oracle Linux pam_lastlog)은
# 진단과 무관하다. log_output/general_log 는 이 테스트가 쿼리 로그를 켜고 끄느라 바꾸므로 서버 스냅샷에서 뺐다.
proc = subprocess.run([sys.executable, "lib/tests/run_safety_check.py", os.path.join(work, "rs"), f"dbms/{engine}",
                       "--allow-fs", r"^[<>] /var/log(/lastlog)?\|", "--nr-same"],
                      capture_output=True, text=True, encoding="utf-8", errors="replace")
if not proc.stdout.strip():
    fails.append("run_safety_check.py 출력 없음(/rs 수집 실패?)")
elif proc.returncode != 0:
    fails.append("run_safety_check.py FAIL\n" + proc.stdout.rstrip())

# ② 일반 OS 계정 실행 = 관리자 OS 계정 실행(항목별 상태)
def items(p):
    try:
        return {it["code"]: it["status"] for it in json.loads(read(p))["items"]}
    except (TypeError, ValueError, KeyError):
        return None
root, nr = items("rs/root.json"), items("rs/nr.json")
if root is None or nr is None:
    fails.append(f"관리자/일반 계정 결과 없음(root={root is not None}, nr={nr is not None})")
else:
    diff = [f"{c}: 관리자={root.get(c)} 일반={nr.get(c)}" for c in sorted(set(root) | set(nr)) if root.get(c) != nr.get(c)]
    if diff:
        fails.append("원격 DB 진단인데 OS 계정에 따라 판정이 다름\n    " + "\n    ".join(diff))

# ③ DB 서버 상태 스냅샷 동일
s0, s1 = read("snap0"), read("snap1")
if not s0 or not s1:
    fails.append("DB 서버 상태 스냅샷 수집 실패(검증 불가)")
elif s0 != s1:
    a, b = s0.splitlines(), s1.splitlines()
    gone = [l for l in a if l not in b][:15]
    new = [l for l in b if l not in a][:15]
    fails.append("진단 전후 DB 서버 상태(설정·계정·권한)가 다름\n    " + "\n    ".join([f"< {l[:160]}" for l in gone] + [f"> {l[:160]}" for l in new]))
else:
    notes.append(f"DB 서버 상태 스냅샷 {len(s0.splitlines())}줄 동일")

# ④ DB 가 받은 문장 - 모두 읽기 전용
raw_log = read("sql.log") or ""
records = []
if engine == "mysql":
    own = {"SET GLOBAL general_log='OFF'"}
    for line in raw_log.splitlines():
        line = line.strip()
        if line:
            try:
                records.append(bytes.fromhex(line).decode("utf-8", "replace"))
            except ValueError:
                fails.append(f"general_log HEX 해석 실패: {line[:80]}")
else:
    own = set()
    on = False
    for row in csv.reader(io.StringIO(raw_log)):
        if len(row) < 14:
            continue
        msg = row[13]
        if "kisa_sql_begin" in msg:
            on = True; continue
        if "kisa_sql_end" in msg:
            on = False; continue
        if on and msg.startswith("statement: "):
            records.append(msg[len("statement: "):])
stmts = []
for r in records:
    if r.strip().rstrip(";").strip() in own:
        continue
    stmts += [p.strip() for p in _sql_strip(r).split(";") if p.strip()]
bad = [s for s in stmts if not sql_is_readonly(s)]
if not stmts:
    fails.append("DB 쿼리 로그가 비어 있음(수집 실패 - 검증 불가)")
elif bad:
    fails.append(f"읽기 전용이 아닌 문장 {len(bad)}건\n    " + "\n    ".join(b[:200] for b in bad[:20]))
else:
    notes.append(f"DB 로 보낸 문장 {len(stmts)}건(관리자·일반 OS 계정 실행 합계) 모두 읽기 전용")

print(("FAIL" if fails else "PASS") + f": {label}")
for f in fails:
    print("  - " + f.lstrip(" -"))
for n in notes:
    print("  · " + n)
for line in proc.stdout.splitlines():
    if line.startswith("  · "):
        print(line)
tmp.cleanup()
sys.exit(1 if fails else 0)
PYEOF
        rm -f "${work}rs.tar" "${work}snap0.tar" "${work}snap1.tar" "${work}sql.tar" "${work}sql.log"
    fi
    docker rm -f "$srv" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
done

# ---- 조치(fix) 회귀 테스트 (조치 후속 F-R6) -----------------------------------------------------------
# 진단이 넓어진 범위(MySQL D-11 전역·테이블 권한, PostgreSQL D-08 md5 로 저장된 role)를 조치가 다루는지, 자동으로 바꿀 수
# 없는 부분은 PARTIAL_MANUAL 로 남기고 원복하지 않는지, 원복(--rollback)이 실제로 되돌리는지 확인한다.
# 클라이언트 컨테이너 안의 시나리오가 "KEY=값" 줄을 출력하고, 여기서 기대값과 비교한다.
# 둘 다 confirm 등급(fix.sh 가 /dev/tty 에서 y/N 을 읽음)이고 PostgreSQL D-08 은 role 비밀번호도 터미널에서 입력받으므로
# script(1)로 가상 터미널을 붙여 답을 넣는다(Dockerfile.mysql 에 util-linux 추가).
fix_expect() {  # fix_expect <출력 파일> <라벨> <KEY=값>...
    _fo=$1; _fl=$2; shift 2
    _fbad=""
    for _kv in "$@"; do
        grep -qx "$_kv" "$_fo" || _fbad="$_fbad $_kv(실제: $(grep "^${_kv%%=*}=" "$_fo" | head -n1))"
    done
    if [ -n "$_fbad" ]; then
        echo "FAIL: $_fl -$_fbad"; sed 's/^/    | /' "$_fo" | tail -n 40; fail=1
    else
        echo "PASS: $_fl"
    fi
}

for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    net="kisa-db-fix-net-$$-$engine"
    srv="kisa-db-fix-srv-$$-$engine"
    docker network create "$net" >/dev/null
    if [ "$engine" = "mysql" ]; then
        docker run -d --name "$srv" --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8 >/dev/null
    else
        docker run -d --name "$srv" --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16 >/dev/null
    fi
    ready=0; i=0
    while [ "$i" -lt 30 ]; do
        if [ "$engine" = "mysql" ]; then
            docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
        else
            docker run --rm --network "$net" "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
        fi
        i=$((i + 1)); sleep 2
    done
    fo="$TMPW/fix_${engine}.out"
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: $engine/fix - DB 서버가 60초 내에 준비되지 않음"; fail=1
    elif [ "$engine" = "mysql" ]; then
        # ① DB 단위(mysql.*)·테이블 단위(mysql.user) 권한만 있으면 회수 → APPLIED·재검증 GOOD, --rollback 으로 GRANT 복원
        # ② 전역 권한(*.*) 계정이 더해지면 DB/테이블 권한은 회수하되 전역 권한은 남기고 PARTIAL_MANUAL(원복하지 않음)
        docker run --rm --name "kisa-db-fix-cli-$$-mysql" --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c '
            export MYSQL_PWD="$DB_PASSWORD"
            M="mysql -h dbhost -uroot -N -B"
            mysql_grants() { $M -e "SHOW GRANTS FOR $1" 2>/dev/null | grep -c " ON \`mysql\`\."; }
            fixst() { awk -F"\t" "\$2 == \"D-11\" { print \$4 }" "$1"/*/changes.log | tail -n1; }
            run_d11() { sh 08_dbms/run.sh -e mysql --host dbhost --user root -i D-11 -o "$1" >/dev/null 2>&1; sed -n "s/.*\"code\": *\"D-11\", *\"status\": *\"\([A-Z]*\)\".*/\1/p" "$1"/*/result.json | head -n1; }
            $M -e "CREATE USER '\''fx_db'\''@'\''%'\'' IDENTIFIED BY '\''FxPass#1234'\''; GRANT SELECT ON mysql.* TO '\''fx_db'\''@'\''%'\'' WITH GRANT OPTION; CREATE USER '\''fx_tbl'\''@'\''%'\'' IDENTIFIED BY '\''FxPass#1234'\''; GRANT SELECT, UPDATE ON mysql.user TO '\''fx_tbl'\''@'\''%'\'';"
            echo "M1_BEFORE=$(run_d11 /tmp/r1)"
            printf "y\n" | script -qec "sh 08_dbms/fix.sh -e mysql --host dbhost --user root -r /tmp/r1/*/result.json -i D-11 --apply --yes -o /tmp/f1" /dev/null >/tmp/f1.out 2>&1
            echo "M1_FIX=$(fixst /tmp/f1)"
            echo "M1_AFTER=$(run_d11 /tmp/r2)"
            echo "M1_DB_GRANTS=$(mysql_grants "'\''fx_db'\''@'\''%'\''")"
            sh 08_dbms/fix.sh -e mysql --host dbhost --user root --rollback "$(ls -d /tmp/f1/*/ | head -n1)" >/tmp/rb1.out 2>&1
            echo "M1_RB_RC=$?"
            echo "M1_RB_DB_GRANTS=$(mysql_grants "'\''fx_db'\''@'\''%'\''")"
            echo "M1_RB_TBL_GRANTS=$(mysql_grants "'\''fx_tbl'\''@'\''%'\''")"
            echo "M1_RB_STATUS=$(run_d11 /tmp/r3)"
            $M -e "CREATE USER '\''fx_glob'\''@'\''%'\'' IDENTIFIED BY '\''FxPass#1234'\''; GRANT SELECT ON *.* TO '\''fx_glob'\''@'\''%'\'';"
            run_d11 /tmp/r4 >/dev/null
            printf "y\n" | script -qec "sh 08_dbms/fix.sh -e mysql --host dbhost --user root -r /tmp/r4/*/result.json -i D-11 --apply --yes -o /tmp/f2" /dev/null >/tmp/f2.out 2>&1
            echo "M2_FIX=$(fixst /tmp/f2)"
            echo "M2_DB_GRANTS=$(mysql_grants "'\''fx_db'\''@'\''%'\''")"
            echo "M2_GLOBAL_KEPT=$($M -e "SELECT Select_priv FROM mysql.user WHERE user='\''fx_glob'\''")"
            echo "M2_AFTER=$(run_d11 /tmp/r5)"
            grep -q "수동 조치 필요" /tmp/f2.out && echo "M2_MANUAL_MSG=yes"
        ' > "$fo" 2>&1 || true
        fix_expect "$fo" "mysql/fix D-11" M1_BEFORE=VULN M1_FIX=APPLIED M1_AFTER=GOOD M1_DB_GRANTS=0 \
            M1_RB_RC=0 M1_RB_DB_GRANTS=1 M1_RB_TBL_GRANTS=1 M1_RB_STATUS=VULN \
            M2_FIX=PARTIAL_MANUAL M2_DB_GRANTS=0 M2_GLOBAL_KEPT=Y M2_AFTER=VULN M2_MANUAL_MSG=yes
    else
        # password_encryption=md5 상태에서 만든 role(md5 해시) + 전역 설정 md5.
        # ① 대화형: 조치 승인 y, role 비밀번호 재설정은 건너뜀(n) → GUC 만 바꾸고 PARTIAL_MANUAL(원복하지 않음)
        # ② --rollback → password_encryption 이 md5 로 돌아옴(ALTER SYSTEM 원복이 트랜잭션 블록 오류 없이 실행)
        # ③ 대화형: y, y, 새 비밀번호 2회 → APPLIED·재검증 GOOD, role 이 SCRAM 해시·새 비밀번호로 로그인, 비밀번호는 조치 결과 폴더
        #    (changes.log·backup)에 없음. script 의 화면 기록(/tmp/f3.out)은 입력을 미리 한꺼번에 넣어 에코되므로 검사 대상에서 뺀다.
        docker run --rm --name "kisa-db-fix-cli-$$-postgres" --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c '
            export PGPASSWORD="$DB_PASSWORD"
            P="psql -h dbhost -U postgres -qAtX"
            fixst() { awk -F"\t" "\$2 == \"D-08\" { print \$4 }" "$1"/*/changes.log | tail -n1; }
            run_d08() { sh 08_dbms/run.sh -e postgres --host dbhost --user postgres -i D-08 -o "$1" >/dev/null 2>&1; sed -n "s/.*\"code\": *\"D-08\", *\"status\": *\"\([A-Z]*\)\".*/\1/p" "$1"/*/result.json | head -n1; }
            fix_tty() { printf "$1" | script -qec "sh 08_dbms/fix.sh -e postgres --host dbhost --user postgres -r $2 -i D-08 --apply --yes -o $3" /dev/null > "$3.out" 2>&1; }
            $P -c "ALTER SYSTEM SET password_encryption = '\''md5'\''" -c "SELECT pg_reload_conf()" >/dev/null
            sleep 1
            $P -c "CREATE ROLE fx_md5 LOGIN PASSWORD '\''FxOld#1234'\''" >/dev/null
            echo "P0_HASH=$($P -c "SELECT left(rolpassword, 3) FROM pg_authid WHERE rolname = '\''fx_md5'\''")"
            echo "P1_BEFORE=$(run_d08 /tmp/r1)"
            fix_tty "y\nn\n" "/tmp/r1/*/result.json" /tmp/f1
            echo "P1_FIX=$(fixst /tmp/f1)"
            echo "P1_GUC=$($P -c "SHOW password_encryption")"
            echo "P1_HASH=$($P -c "SELECT left(rolpassword, 3) FROM pg_authid WHERE rolname = '\''fx_md5'\''")"
            grep -q "수동 조치 필요" /tmp/f1.out && echo "P1_MANUAL_MSG=yes"
            sh 08_dbms/fix.sh -e postgres --host dbhost --user postgres --rollback "$(ls -d /tmp/f1/*/ | head -n1)" >/tmp/rb1.out 2>&1
            echo "P2_RB_RC=$?"
            echo "P2_GUC=$($P -c "SHOW password_encryption")"
            run_d08 /tmp/r2 >/dev/null
            fix_tty "y\ny\nFxNew#98765\nFxNew#98765\n" "/tmp/r2/*/result.json" /tmp/f3
            echo "P3_FIX=$(fixst /tmp/f3)"
            echo "P3_AFTER=$(run_d08 /tmp/r3)"
            echo "P3_HASH=$($P -c "SELECT left(rolpassword, 5) FROM pg_authid WHERE rolname = '\''fx_md5'\''")"
            echo "P3_LOGIN=$(PGPASSWORD="FxNew#98765" psql -h dbhost -U fx_md5 -d postgres -qAtX -c "SELECT 1" 2>/dev/null)"
            echo "P3_PW_LEAK=$(grep -rl "FxNew#98765" /tmp/f1 /tmp/f3 /tmp/r3 2>/dev/null | grep -c .)"
        ' > "$fo" 2>&1 || true
        fix_expect "$fo" "postgres/fix D-08" P0_HASH=md5 P1_BEFORE=VULN P1_FIX=PARTIAL_MANUAL P1_GUC=scram-sha-256 P1_HASH=md5 \
            P1_MANUAL_MSG=yes P2_RB_RC=0 P2_GUC=md5 P3_FIX=APPLIED P3_AFTER=GOOD P3_HASH=SCRAM P3_LOGIN=1 P3_PW_LEAK=0
    fi
    rm -f "$fo"
    docker rm -f "$srv" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
done

exit $fail

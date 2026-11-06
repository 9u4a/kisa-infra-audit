# 릴리스 체크리스트

태그를 만들기 전에 위에서부터 차례로 확인합니다. 하나라도 실패하면 태그를 만들지 않습니다.

## 1. 코드·테스트
- [ ] main 의 최근 push CI 가 전부 녹색이다 (`gh run list --branch main --limit 1`)
- [ ] 주간·수동 job 까지 전 job 을 수동 실행해 녹색을 확인했다
  - `gh workflow run test.yml --ref main` → oracle, mssql-express, engine-matrix, windows-2022 matrix 포함
- [ ] 커버리지 누락 0: `python3 lib/tests/coverage.py --strict`
- [ ] 조치 등급 일관성: `python3 lib/tests/guide_consistency.py`
- [ ] 실패한 job 을 재실행해 통과했다면, 원인을 KNOWN_ISSUES 나 CHANGELOG Fixed 에 남겼다

## 2. 문서
- [ ] `VERSION` 을 새 버전으로 올렸다 (기능 추가 = MINOR, 판정 수정·버그 = PATCH)
- [ ] `CHANGELOG.md` 의 `[Unreleased]` 를 `[x.y.z] - YYYY-MM-DD` 로 바꾸고, 빈 `[Unreleased]` 를 새로 두었다
- [ ] README
  - 맨 위 한눈에 표의 숫자(항목 수, 양방향 / 면제 / 누락, CI 환경 수, 결함 수)가 실측과 같다
  - 검증 환경 표의 버전이 이번 CI job summary("엔진 버전 기록")와 같다
  - "x.y.z 예정" 표시를 지웠다
  - 로드맵 행을 ✅ 로 바꿨다
- [ ] `KNOWN_ISSUES.md` 에서 이번 버전에 해결한 ID 의 상태를 `해결(x.y.z)` 로 바꿨다

## 3. 공개 전 확인
- [ ] 커밋·태그·릴리스 본문에 도구 서명·세션 식별자가 없다
  - `git log <이전 태그>..HEAD --format=%B | grep -iE "claude|session"` 결과가 비어 있다
- [ ] 로컬 전용 파일이 추적되지 않는다
  - `git ls-files | grep -iE "^(output|\.claude|\.githooks)/|CLAUDE\.md|PORTFOLIO\.md|\.pdf$"` 결과가 비어 있다
- [ ] 결과물·픽스처에 실제 호스트명·IP·비밀번호가 없다 (`lib/tests/fixtures/locale/` 등 실기 수집본 포함)

## 4. 태그·릴리스
```sh
git checkout main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <CHANGELOG 해당 절을 옮긴 파일>
```
- [ ] `gh release view vX.Y.Z` 로 릴리스가 보인다

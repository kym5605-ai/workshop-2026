# 2026 워크샵 코스 투표 페이지

팀원 10명이 워크샵 코스를 투표로 정하는 단일 페이지입니다. claude.ai 채팅에서 만들고 이 저장소로 옮겨 왔습니다.

## 배포
- 저장소: github.com/kym5605-ai/workshop-2026 (공개)
- 주소: https://kym5605-ai.github.io/workshop-2026/
- GitHub Pages: main 브랜치 / 루트. `index.html`을 main에 푸시하면 1~2분 뒤 반영됩니다. 빌드 과정은 없습니다.

## 구조
- `index.html` 하나에 HTML·CSS·JS·사진(base64)이 모두 들어 있습니다. 외부 의존은 Pretendard 폰트(jsdelivr)와 Supabase REST뿐입니다.
- 화면은 해시 라우팅입니다: `#overview` `#courses` `#course-1` `#course-2` `#vote` `#result` `#party` `#party-result` `#final`. 내부 이동은 `go('#뷰')`를 씁니다.
- 데이터 상수: `COURSES`(코스 1·2: 타임테이블, 비용, 경로, 숙소/파티룸), `STAY_PHOTOS` `THEK_PHOTOS` `CAMP_PHOTOS` `LOOPL_PHOTOS`(사진), `PEOPLE=10` `VOTERS=10` `BASE=900000`(회사 지원금).
- 비용 표기 규칙: 회사 지원 90만원 차감·1인 추가 부담은 **최종 결과 페이지에만** 표시합니다. 코스 카드·상세·투표 화면에는 넣지 않습니다.

## 투표 흐름
1. 코스 1·2 중 1표 (명단에서 본인 이름 선택, 이름당 1표, 기기 토큰으로 잠금)
2. 공개 기준 인원이 차면 결과가 자동 공개되고, 열려 있는 모든 화면에 알림 시트가 뜬 뒤 결과 화면으로 이동
3. 코스 2가 이기면 파티룸 3곳(thek 더케이, camp 캠퍼블릭, loopl 루플) 중 1표 → 같은 방식으로 자동 공개
4. 모든 투표가 끝나면 `#final`에 최종 요약
- 동점이면 멈추고 관리자가 결정합니다. 페이지는 3초마다 상태를 확인합니다.

## 백엔드 (Supabase)
- 프로젝트: vinu 조직 / vinu-ad-creative (ref `ojxxhgzxcbhcsdfsjqhw`, 서울 리전). 다른 서비스와 같은 프로젝트라 **ws26_ 로 시작하는 객체만** 건드립니다.
- 테이블: `ws26_state`(설정 jsonb: round, threshold, names, forced_c/p, final_c/p, budget, deadline), `ws26_ballots`(round, voter, token, course, venue), `ws26_secret`(관리자 PIN). 모두 RLS 켜짐·정책 없음 → 직접 접근 불가.
- 함수(RPC, anon 실행 가능, security definer):
  - `ws26_status(p_token)` 현재 상태. 공개 전에는 집계를 반환하지 않습니다.
  - `ws26_vote(p_name, p_token, p_kind 'course'|'venue', p_value)`
  - `ws26_admin(p_pin, p_action, p_value)` action: check, threshold, names, budget, deadline, forced_c, forced_p, final_c, final_p, new_round, reset_flags
- 스키마 전체: `supabase-setup.sql` (PIN 자리는 비워 두었습니다).
- 클라이언트에 있는 publishable 키는 공개용이라 저장소에 있어도 됩니다. **관리자 PIN은 저장소에 절대 넣지 마세요.** PIN은 건우님만 알고 있습니다.

## 관리자 운영
- 개요 화면 맨 아래 「관리자」에 PIN 입력 → 명단, 공개 기준, 예산 표기, 강제 공개, 동점 결정, 초기화.
- 배포 전 체크: 명단 10명 저장 → 기준 10명 → 「전체 투표 새로 시작」(round 교체로 기존 표 무시) → 링크 공유.

## 디자인 규칙 (사용자 선호)
- 가을 톤, 캐치테이블 모티브: 흰 배경 + 감색 주황 포인트(`--accent`) + 밤색 보조(`--deep`). 색은 최소한으로.
- 서체는 프리텐다드, 굵은 산세리프. 명조·세리프 금지. 이모지 금지.
- 문구는 「~합니다」 존댓말, 짧게. 텍스트보다 사진·표·그래프 위주.
- 모바일 우선 반응형(768px·1100px 분기), 라이트/다크 모두 지원.

## 수정 후 확인할 것
- 9개 화면이 모두 오류 없이 열리는지, 가로 스크롤이 생기지 않는지(390px·1280px)
- 공개 기준 1명으로 놓고 코스 2 → 파티룸 → 최종 결과까지 혼자 끝까지 진행되는지

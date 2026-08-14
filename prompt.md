# UI 통합 작업 지시서 (prompt.md)

> 자동 생성 — publish마다 갱신됩니다. 직접 수정 금지.
> 사용법(사람): 게임 AI에게 "prompt.md 를 읽고 UI 를 통합해줘" 라고 지시하면 됩니다.

이 프로젝트의 UI 는 ui-editor publish 산출물이다 — 재구현 금지·읽기 전용 규칙은 루트 `AGENTS.md` 참조.
publish 폴더는 `./web/ui/` (publish-report.json·scene-flow.json·contract 파일이 있는 곳).

**통합 절차의 정본은 `.claude/skills/ui-editor-game/SKILL.md`** — Codex 는 `.codex/skills/ui-editor-game/SKILL.md` 동일본, 스킬 자동 인식이 없는 도구는 그 파일을 직접 읽는다.

1. 스킬 **§0 작업 절차**를 따른다 — 읽는 순서(publish-report → scene-flow-changes → scene-flow + SCENES.md → PROMO.md), 미배선 수리 루프(자가진단 되먹임 소비), 역질문 규약(추측 구현 금지).
2. 배선 방법은 스킬 §6(scene-flow), 매니저 API 는 §4, 실전 함정 체크리스트는 §3.

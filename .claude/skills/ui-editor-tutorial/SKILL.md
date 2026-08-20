---
name: ui-editor-tutorial
description: 튜토리얼로 특정 버튼·영역의 터치를 유도할 때 사용. 손가락 포인터·파동(리플) 표시, 주변만 밝히고 나머지를 암전하는 포커싱(스포트라이트), 안내 문구 표시와 위치 자동 조정, 그 버튼을 눌러야만 다음 단계로 넘어가는 진행 게이팅, 첫 진입 가이드·튜토리얼 단계 시퀀스 구현 요청이 오면 이 스킬을 따른다.
---

# 튜토리얼 터치 힌트

구현체는 publish 출력 폴더의 `tutorial-hint.js` 하나다. **새로 만들지 말고 이걸 쓴다.**
암전 div·포인터 이미지·리플 애니메이션을 튜토리얼마다 다시 만드는 것이 이 스킬이 막는 일이다.

**publish 산출물(읽기 전용)** — ui-editor 가 저장 publish 마다 최신본으로 덮어쓴다. 이 파일을 직접
수정하면 다음 publish 때 사라진다. 튜닝은 전부 `configure()` 로 게임 코드에서 한다.

## API

```js
import TutorialHint from './tutorial-hint.js';

await TutorialHint.step({ target, text, radius });      // 탭: 타깃을 누를 때까지 대기 (핵심)
await TutorialHint.drag({ from, to, text, radius });    // 드래그: 모션만 재생, hide() 로 종료
TutorialHint.show(target);                              // 손가락·파동만 (암전·문구·게이팅 없음)
TutorialHint.hide();                                    // 강제 종료 — 대기 중인 step/drag 도 함께 풀린다
TutorialHint.configure({ dim: 0.6, cycle: 1400 });     // 튜닝 오버라이드 — 첫 show/step 전에
```

| 인자 | 기본 | 설명 |
|---|---|---|
| `target` / `from` `to` | 필수 | Element · CSS 선택자 · `{x,y}`(viewport 좌표) |
| `text` | `''` | 안내 문구. 타이핑으로 출력되고, **끝난 뒤에야** 손가락이 나온다 |
| `radius` | 자동 | 밝은 원의 반경(px). 생략 시 타깃 대각선/2 + 12 |

`step()` 이 resolve 되는 시점 = 사용자가 그 타깃을 실제로 누른 시점. 타깃의 원래 `click` 핸들러도 함께
실행되므로 **튜토리얼용 분기 코드를 게임 쪽에 심지 말 것**.

## 드래그 (`drag`)

출발에서 누르고 도착까지 끌었다 떼는 손 모션을 반복 재생한다. **판정은 하지 않는다** — 어디서 어디로
끄는지도, 성공 시점도 게임이 정한다. 게임의 드래그 로직이 성공하면 `hide()` 를 부르고, 그때 `drag()` 의
Promise 가 풀린다.

```js
const guide = TutorialHint.drag({
  from: renderer.getElement('tile-1'),
  to:   renderer.getElement('slot-3'),
  text: '조각을 빈 칸으로 끌어오세요.',
});
// 게임의 드롭 성공 처리부에서:  TutorialHint.hide();
await guide;
```

탭 단계와 달리 **암전이 없다.** 구멍이 출발~도착을 다 덮을 만큼 커지면 어느 영역인지 분간이 안 되고,
입력을 통과시켜야 게임이 드래그를 받으므로 게이팅도 못 한다 — 암전이 할 일이 없다. 문구와 손 모션만
나오고, 문구는 드래그 경로를 가리지 않는 쪽(위/아래)에 붙는다.

`configure()` 키: `handSrc` `tipX` `tipY` `handW` `ring` `dot` `cycle` `dragCycle` `dim` `feather`
`msgGap` `typeMs` — 의미와 기본값은 tutorial-hint.js 상단 `cfg` 주석 참조. CSS 는 첫 사용 때 한 번 생성되므로
반드시 첫 show/step 전에 호출한다.

## 씬 버튼을 타깃으로 잡기

씬 레이어는 `stableId` 로 꺼낸다(값은 루트 `SCENES.md`·`*.contract.json`).

```js
await TutorialHint.step({
  target: renderer.getElement('btn-3'),
  text: '이 버튼을 눌러 전투를 시작하세요.',
});
```

씬이 표시된 **뒤에** 호출한다 — 씬 전환은 DOM을 새로 만들므로 전환 전에 잡은 요소는 죽은 노드다.

## 단계 시퀀스

```js
if (!localStorage.getItem('tut.intro')) {
  await TutorialHint.step({ target: renderer.getElement('btn-play'), text: '여기서 시작합니다.' });
  await TutorialHint.step({ target: renderer.getElement('btn-shop'), text: '아이템은 여기서 삽니다.' });
  localStorage.setItem('tut.intro', '1');
}
```

튜토리얼 진행 상태를 담는 매니저는 프로젝트에 없다. 위처럼 플래그 하나로 두고, 서버 저장이 필요해지면
`ProgressManager` 쪽에 얹을지 사용자에게 묻는다.

## 규약 (건드리기 전에 알아야 하는 것)

- **동시에 하나만.** 두 곳을 동시에 가리키면 시선이 갈라진다. 여러 곳을 안내해야 하면 단계로 쪼갠다.
- **구멍 밖 입력은 전부 차단된다.** 암전판이 화면 전체 클릭을 삼키고 반경 안만 통과시킨다. 그래서
  타깃은 `pointer-events` 가 살아 있고 `disabled` 가 아닌, 실제로 클릭 가능한 요소여야 한다.
- **문구 위치는 자동.** 기본 상단, 밝은 원과 겹치면 하단. 좌우 배치는 없다.
- **손 이미지는 publish 가 함께 심는 `vendor/tutorial-hand.webp`** (모듈 옆 vendor/, 경로 자동 해석).
  게임 고유 손으로 바꾸려면 `configure({ handSrc, tipX, tipY })` — `tipX`/`tipY` 는 손끝 위치의
  알파 채널 실측 비율이라 이미지를 바꾸면 이 두 값을 반드시 다시 잰다(접점 정렬·회전 원점이 파생됨).
- **`handW` 기본 78px 는 390 캔버스 기준.** 뷰포트가 크게 다른 게임은 configure 로 비례 조정.
- 튜토리얼 손가락을 ui-editor 캐릭터 클립으로 만들지 말 것 — 파동 확산이 프레임 보간으로 표현되지
  않아 한 번 실패한 접근이다.

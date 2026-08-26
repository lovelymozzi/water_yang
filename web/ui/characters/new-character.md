# 캐릭터 `new-character` — New Character

ui-editor 캐릭터 메이커 산출물 (`version: 3`).
**이 파일과 `new-character.character.json` 은 발행 때마다 덮어써집니다 — 직접 수정하지 마세요.**

- 캔버스 390×390px
- 실제 그림 영역(기본 자세) `contentBounds`: 없음

## 슬롯 (교체 지점)

| socketId | 이름 | 렌더 | 파츠(partId) |
|---|---|---|---|
| — | 슬롯 없음 | | |

## 클립 (동작)

| clipId | 표시 이름 | 프레임 | 길이 | 반복 |
|---|---|---|---|---|
| — | 클립 없음 | | | |

**호출은 `clipId` 로 하세요.** 표시 이름은 에디터에서 언제든 바뀌고, 바뀌면 이름으로 부르던 코드가 조용히 멈춥니다.

## 붙이는 법

씬에 배치된 캐릭터라면 씬 레이어에서 꺼냅니다.

```js
const hero = renderer.el('<레이어 stableId>').__uiCharacter;
```

인게임(씬 밖)에서 직접 붙일 때. **기준 경로가 둘이고 서로 다릅니다** — 정의는 이 폴더 기준,
이미지는 프로젝트 루트 기준(씬 contract 와 동일 규약)이라 하나로 합칠 수 없습니다.

```js
import { SceneRenderer } from './scene-renderer.js';

const hero = SceneRenderer.mountCharacter(document.getElementById('stage'), 'new-character', {
  defBase:  'src/js',   // characters/ 가 있는 폴더 = 이 md 가 있는 폴더의 상위(publish 출력 폴더)
  basePath: '',         // 이미지 exportPath 의 기준 = 프로젝트 루트 (씬 렌더러와 같은 값)
  equip: {  },
});
```

씬 안의 캐릭터도 같은 정의를 읽으므로, 게임 부팅 시 `SceneRenderer.characterBase = 'src/js'` 를 한 번 지정하세요.

## 조작

```js
hero.equip('socketId', 'partId');  // 교체 ('' 이면 장착 해제)
hero.play('clipId');
hero.play('clipId', { loop: true, onEnd: () => {} });
hero.stop();          // 정지 + 기본 자세 복귀
hero.getEquip();      // 현재 장착 상태
```

정의 로딩은 비동기입니다(`new-character.character.json` fetch). 붙인 직후 `play()` 를 부르면 아직 조립 전일 수 있으니
로딩 뒤에 호출하고, 실패 시 콘솔의 `[SceneRenderer]` 경고를 확인하세요. `play()` 는 못 찾으면 `false` 를 반환합니다.

## 등장/퇴장 · 투사체 인계

프레임 포즈의 `hidden` 은 **보간하지 않는 스텝 트랙**입니다(이전 프레임 값 유지). 이펙트·투사체가
동작 도중 나타났다 사라지는 타이밍이 여기 들어 있습니다. **날아가는 것은 게임 몫**이고, 에디터는
"언제·어디서·어느 방향으로" 만 넘깁니다.

```js
hero.play('clipId', {
  onHide: (poseKey, el, aim) => {          // 에디터의 투사체가 사라지는 순간 = 발사
    if (!aim) return;                       // 조준선 미지정 오브젝트
    spawnArrow(aim.x, aim.y, aim.angleDeg); // aim = client 좌표 + 발사각
  },
  onShow: (poseKey, el, aim) => {},        // 반대 방향 전환(장전 등)
});
```

- `aim` 은 조준선이 그어진 오브젝트에만 옵니다(없으면 `null`).
- `aim.x/y` 는 **client 좌표**(`getBoundingClientRect` 기준)입니다. 스테이지 기준으로 쓰려면
  스테이지의 rect 를 빼세요.
- `angleDeg` 는 0°=오른쪽, 90°=아래 (CSS 회전과 같은 방향).
- 루트에 `scaleX(-1)` 로 좌우 반전을 걸어도 **각도·좌표가 이미 반영되어** 옵니다 — 게임에서 다시
  뒤집지 마세요. 실제 화면 위치를 측정한 값이기 때문입니다.
- 전환 판정 기준선은 기본 자세입니다. `play()` 직후 첫 프레임에서 이미 달라져 있으면 그것도 전환으로 봅니다.

## 조준선 (`aim`)

레이어의 `aim = { x1, y1, x2, y2 }` 는 **원본 박스(`width`×`height`) 기준 0~1 비율**이며
`(x1,y1)`=꼬리, `(x2,y2)`=촉입니다. 화살촉이 그림의 어느 쪽인지는 이미지에서 알아낼 수 없어
에디터에서 사람이 한 번 그어 박아둔 값입니다. 오브젝트 회전 위에 얹히므로 프레임마다 다시 찍지 않습니다.

직접 파싱한다면 두 점을 이미지와 **같은 변환 안**에 두고 화면 좌표로 옮긴 뒤 각도를 재세요
(회전·배율·반전을 숫자로 합성하면 부호를 틀리기 쉽습니다).

## 좌표·변환 규약 (직접 파서를 쓸 때 필수)

렌더러를 쓰지 않고 직접 그린다면 아래 순서를 그대로 지켜야 위치가 맞습니다. 상식적인 "중심 기준 스케일"로
구현하면 어긋납니다.

1. `x/y` = **배율이 반영된 박스의 좌상단**. (`width/height` 는 원본 px, 실제 크기는 `width × scaleX × scale`)
2. **스케일은 좌상단 기준** — `transform-origin: 0 0`.
3. **회전은 원본 크기의 중심 기준** — `transform-origin: 50% 50%`, 스케일보다 **안쪽**에서 적용.

즉 합성 순서는 `translate(x,y) → scale(원점 0 0) → rotate(원점 50% 50%)` 입니다.

```html
<div style="position:absolute; left:{x}px; top:{y}px">
  <div style="transform:scale({scaleX*scale},{scaleY*scale}); transform-origin:0 0">
    <div style="transform:rotate({rotation}deg); transform-origin:50% 50%">
      <img src="{exportPath}" style="width:{width}px; height:{height}px">
```

생략된 값의 기본값: `rotation`=0, `scale`=1, `scaleX`=1, `scaleY`=1, `visible`=true.
**필드가 아예 없을 수 있으니 반드시 기본값으로 채우세요**(에디터는 기본값이면 생략해 방출합니다).

**렌더 순서**: 슬롯의 `z`(front/back)가 몸통 앞/뒤 블록을 먼저 정하고, 레이어의 `zIndex` 는 그 블록
안에서만 의미를 갖습니다 — 충돌하면 **슬롯 z 가 항상 이깁니다**. 앞 슬롯끼리는 정의의 슬롯 배열 순서대로 겹칩니다.

## 재생 시맨틱

- 프레임 사이는 **선형 보간**입니다. easing 필드는 없습니다. 스텝(뚝뚝 끊기는 스톱모션)으로 보이게 하려면
  같은 자세의 프레임을 촘촘히 두 개 찍는 방식으로 저작합니다.
- 프레임 시각(`tMs`)은 임의입니다. **0ms 프레임이 반드시 있지는 않습니다** — 첫 프레임 이전 구간은 첫 프레임 자세로 고정됩니다.
- 클립 길이 = 마지막 프레임의 `tMs`.
- `loop:false` 는 **마지막 프레임 자세로 정지**합니다(기본 자세로 자동 복귀하지 않음). 기본 자세로 되돌리려면 `stop()` 을 부르세요.
  끝 자세와 기본 자세가 다르면 화면이 끊겨 보이므로, 필요하면 게임 쪽에서 짧게 블렌딩하세요.
- 클립이 언급하지 않은 오브젝트는 기본 자세를 유지합니다.

## 기본 자세

`base` / `parts[].layers` 의 좌표가 곧 **기본 자세**입니다. 클립의 어떤 프레임과도 무관하며,
에디터에서도 "기본 자세" 칸에서만 편집됩니다. 게임이 클립을 재생하지 않으면 항상 이 자세입니다.

## 좌우 반전

전체 반전은 **루트 엘리먼트에 `transform: scaleX(-1)`** 을 거세요.
파츠를 개별로 반전하면 슬롯의 앞/뒤와 상대 위치가 깨집니다 — 하지 마세요.

## 하지 말아야 할 것

슬롯·파츠·클립을 코드로 새로 만들지 마세요. 필요한 것이 없으면 ui-editor 캐릭터 메이커에 추가를 요청하세요.
`characters/index.json` 에 발행된 캐릭터 목록이 있습니다.

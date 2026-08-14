---
name: ui-editor-security
description: 게임 빌드를 완성한 뒤 배포 전에 보안 검수를 수행할 때 사용. 빌드 내 민감정보(API 키·토큰·계정·내부 URL) 스캔, 밸런싱·맵데이터 등 게임 데이터 JSON 암호화와 키 쪼개기, 치트 표면(localStorage 변조·전역 노출·디버그 잔재) 점검, XSS·인젝션 점검, 배포 파일 위생 검사 요청이 오면 이 스킬을 따른다. 진행은 반드시 전체 스캔 리포트 → 개발자 승인 → 승인된 항목만 조치 순서로 한다.
---

<!-- 자동생성: ui-editor publish가 이 파일을 게임 프로젝트에 복사·갱신한다. 직접 수정 금지(수정은 ui-editor 저장소 game-skill/에서). -->

# 게임 빌드 보안 검수 가이드

게임 개발사 수준에서 **배포 직전 빌드**를 검수한다. 퍼블리셔/인프라 보안(WAF·서버 하드닝 등)은 범위 밖이다. 검수 대상은 실제로 배포될 파일 집합 전체(게임 코드·데이터·에셋·산출물)다.

## 0. 동작 규약 — 리포트 → 승인 → 조치

1. **전체 스캔 먼저.** 아래 A~F 카테고리를 모두 수행하고, 발견 사항을 심각도별 표로 리포트한다. 스캔 중에는 아무것도 수정하지 않는다.

   | # | 심각도 | 카테고리 | 발견 내용 | 근거(파일:라인) | 제안 조치 |
   |---|---|---|---|---|---|

   심각도: **Critical**(즉시 유출 — 키·계정), **High**(치트·변조·XSS 가능), **Medium**(정보 노출·취약 의존성), **Low**(위생).
2. **항목별로 개발자 승인을 받은 것만 조치한다.** 승인 없이 일괄 수정 금지. 조치 후 같은 스캔을 재실행해 잔존 여부를 리포트한다.
3. **외부 조치는 안내만.** 이미 커밋·배포된 키의 회전(재발급), 서버 측 검증 도입 같은 것은 코드로 대신할 수 없다 — 리포트에 절차를 적고 개발자가 수행한다.
4. **거짓 안심 금지.** 확신 없는 항목은 심각도를 낮추지 말고 "확인 필요"로 표기한다. 스캔하지 못한 영역(바이너리·난독화된 서드파티 등)은 리포트에 명시한다.

## 1. [A] 민감정보 스캔 — Critical

배포 파일 전체(텍스트·JSON·JS·HTML·소스맵)를 대상으로:

```bash
# 키·토큰 패턴 (대표 예 — 프로젝트에 맞게 확장)
grep -rnE 'AKIA[0-9A-Z]{16}' .                                  # AWS Access Key
grep -rnE 'AIza[0-9A-Za-z_-]{35}' .                             # Google API Key
grep -rnE 'eyJ[A-Za-z0-9_-]{20,}\.eyJ' .                        # JWT (Supabase anon/service 키 포함)
grep -rnE '-----BEGIN( RSA| EC)? PRIVATE KEY-----' .            # 개인키
grep -rniE '(api[_-]?key|secret|token|passwd|password|credential)["'"'"']?\s*[:=]' .
# 계정·내부 정보
grep -rniE '(localhost|127\.0\.0\.1|192\.168\.|10\.[0-9]+\.|staging\.|dev\.|\.internal)' .
grep -rnE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|net|kr|jp)' . # 이메일(사내 도메인 특히)
```

- **개발 잔여물 탐지**: `.env`·`.env.*`, `.git/`, `*.map`(소스맵 — 원본 소스 통째 노출), `.DS_Store`, `*.bak`·`*~`·`*.orig`, `test-*`·`mock-*`·`*.spec.js` 류가 배포 집합에 있으면 안 된다.
- **주석 점검**: 실명·내부 이슈 URL·"임시로 키 하드코딩" 류 TODO/FIXME.
- 조치: 파일 제거 또는 값 제거(빌드 시 주입으로 전환). **한 번이라도 배포·커밋된 키는 제거만으로 부족 — 회전(재발급)을 리포트에 필수 안내.** JWT는 payload를 디코드해 `role` 확인 — `service_role`이면 최상급 사고로 표기.

## 2. [B] 게임 데이터 보호 — 밸런싱·맵데이터 JSON 암호화 + 키 쪼개기 — High

빌드 내 평문 게임 데이터 JSON(밸런싱 수치, 스테이지/맵 구조, 드랍·확률 테이블, 정답 데이터)을 찾아 목록화하고, 승인 시 아래 레시피로 암호화한다.

> **위협모델을 정직하게**: 클라이언트에 배포된 이상 키도 함께 배포된다. 이 암호화는 "브라우저 개발자도구·텍스트에디터로 열어 훑어보고 고치는" 수준의 유출·변조를 막는 **억지력**이지 완전 보호가 아니다. 확률 조작·재화 치트를 확실히 막아야 하면 서버 권위(서버가 판정·저장)가 정답이며, 리포트에 이 한계를 반드시 명시한다.

**제외 대상**: ui-editor publish 산출물(`*.contract.json`, `scene-flow.json`, `scenes-index.json`)은 scene-renderer가 평문으로 읽으므로 **암호화하지 않는다**.

### 빌드 스텝 (Node) — 암호화 + 키 4조각 XOR 분할

```js
// tools/encrypt-data.mjs — node tools/encrypt-data.mjs data/balancing.json
import { webcrypto as wc } from 'node:crypto';
import fs from 'node:fs';
const plain = new TextEncoder().encode(fs.readFileSync(process.argv[2], 'utf8'));
const rawKey = wc.getRandomValues(new Uint8Array(32));
const iv = wc.getRandomValues(new Uint8Array(12));
const key = await wc.subtle.importKey('raw', rawKey, 'AES-GCM', false, ['encrypt']);
const cipher = new Uint8Array(await wc.subtle.encrypt({ name: 'AES-GCM', iv }, key, plain));
const digest = Buffer.from(await wc.subtle.digest('SHA-256', plain)).toString('hex');
// 키 쪼개기: s1^s2^s3^s4 = rawKey — 조각 하나로는 무의미
const s = [0, 1, 2].map(() => wc.getRandomValues(new Uint8Array(32)));
const s4 = rawKey.map((b, i) => b ^ s[0][i] ^ s[1][i] ^ s[2][i]);
fs.writeFileSync(process.argv[2].replace(/\.json$/, '.enc.json'), JSON.stringify({
    v: 1, iv: Buffer.from(iv).toString('base64'),
    data: Buffer.from(cipher).toString('base64'), sha256: digest,
}));
console.log('shards(base64) — 서로 다른 파일에 배치할 것:');
[...s, s4].forEach((x, i) => console.log('s' + (i + 1) + ':', Buffer.from(x).toString('base64')));
```

- 조각 배치: `const KEY = "..."` 하나로 grep되지 않게 **서로 다른 파일**에 흩어 넣는다 — 예: s1은 로더 모듈 상수, s2는 유틸 모듈, s3은 별도 설정 청크, s4는 무해한 이름의 데이터 파일. 변수명에 key/secret 단어를 쓰지 않는다.
- 평문 원본(`data/*.json`)은 배포 집합에서 제외하고 소스 저장소에만 둔다.

### 런타임 로더 (브라우저 WebCrypto)

```js
async function loadSecureJson(url, shardsB64) {
    const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    const parts = shardsB64.map(b64);
    const rawKey = parts[0].map((_, i) => parts.reduce((a, p) => a ^ p[i], 0));
    const pkg = await (await fetch(url)).json();
    const key = await crypto.subtle.importKey('raw', rawKey, 'AES-GCM', false, ['decrypt']);
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64(pkg.iv) }, key, b64(pkg.data));
    const hex = [...new Uint8Array(await crypto.subtle.digest('SHA-256', plain))]
        .map((b) => b.toString(16).padStart(2, '0')).join('');
    if (hex !== pkg.sha256) throw new Error('데이터 변조 감지: ' + url); // 무결성 대조
    return JSON.parse(new TextDecoder().decode(plain));
}
```

- AES-GCM은 자체 인증태그로 변조 시 decrypt가 실패하고, sha256 대조는 평문 차원의 이중 확인이다.
- 이미 같은 역할의 로더/암호화 스텝이 프로젝트에 있으면 **재사용**하고 새로 만들지 않는다.

## 3. [C] 클라이언트 신뢰 / 치트 표면 — High

- **localStorage 평문 상태**: 재화·진행도가 평문으로 저장되면 개발자도구로 즉시 변조된다. ui-editor 산출물인 `economy-manager.js`(하트·코인)·`progress-manager.js`(진행도)는 기본이 클라이언트 신뢰 모델(LOCAL_AUTHORITY)이며 **읽기 전용이라 수정 대상이 아니다**. 판정 기준: 싱글플레이(치팅 피해자가 본인뿐)면 현상 유지로 통과. **리더보드·유저 경쟁 이벤트·실물 보상이 있으면** 게임 서버로 Authority 계약(`game-session.js` 상단 주석, 주입법은 `ui-editor-game` 스킬 §4)을 구현해 주입하라고 리포트에 권고한다. HMAC 등 클라이언트 서명은 권고하지 않는다 — 키가 클라이언트에 있어 콘솔 호출로 우회되며, 정상 유저 세이브 무효화 위험만 남는다. 경쟁 표면 게임에서 리더보드 제출값이 클라이언트 저장값(`getBestScore()` 등)을 그대로 쓰는 경로가 있으면 **그 자체를 High 로 보고**한다.
- **전역 노출**: `window.economy = ...`처럼 매니저·게임 인스턴스를 전역에 두면 콘솔 한 줄로 치트가 된다. `grep -rnE 'window\.[a-zA-Z]+\s*=' .`로 노출 목록화.
- **디버그 잔재**: 치트키·무적모드·스테이지 스킵·`?debug=` 류 플래그가 배포 빌드에 남아있는지. `grep -rniE '(cheat|godmode|debug|skipstage|devmode)' .`
- **콘솔 유출**: `console.log`로 정답 데이터(퍼즐 해답·드랍 확률)·세션 값이 흘러나오는지.

## 4. [D] 인젝션 / XSS — High

- `innerHTML`·`insertAdjacentHTML`·`document.write`에 **외부·저장 데이터**(URL 파라미터, 서버 응답, localStorage 값)가 들어가는 경로. 정적 문자열만 쓰면 통과.
- `eval(`·`new Function(` 사용처 — 데이터가 코드로 실행되는 통로.
- `postMessage`/카트리지 post 이벤트 **수신부**: origin(발신자) 검증과 payload 스키마 검증 없이 바로 신뢰하는지.
- `http://` 리소스 로드(혼합 콘텐츠) — 전부 `https://`로.

## 5. [E] 서드파티 / 의존성 — Medium

- 게임이 직접 추가한 라이브러리의 이름·버전을 목록화하고, 알려진 취약 버전인지 웹 검색으로 확인한다. (publish 산출물 `vendor/`는 ui-editor가 관리 — 참고 목록에만 포함.)
- CDN `<script>`/`<link>`에 `integrity`(SRI) 누락 여부 — CDN 오염 시 코드 주입 방지.

## 6. [F] 빌드 위생 — Low~Medium

- 배포 불필요 파일: 원본 작업 파일(PSD·피그마 export 원본), 어느 코드도 참조하지 않는 대용량 에셋, 개발용 문서(`AGENTS.md`·`SCENES.md`·스킬 폴더 등)가 **최종 배포 패키지**에 포함되는지. (개발 저장소에는 있어야 정상 — 배포 집합 기준으로만 판단.)
- 상세 에러를 화면에 그대로 노출(스택트레이스 alert 등)하는 코드.

## 7. 금지 규칙

- [ ] **publish 산출물 수정 금지**: `*.contract.json`, `scene-renderer.js`·`popup-manager.js`·`sound-manager.js`·`game-session.js`·`economy-manager.js`·`progress-manager.js`, `vendor/`, `scenes-index.json`, `scene-flow.json` — 재publish 때 덮어써진다. 발견 사항은 리포트로만 (필요 시 ui-editor 쪽 수정 요청).
- [ ] **승인 없는 수정 금지** — §0 규약. 특히 파일 삭제·암호화 전환은 되돌리기 어려우므로 반드시 승인 후.
- [ ] **중복 함수 금지** — 같은 역할 로더/헬퍼가 이미 있으면 재사용.
- [ ] **추정 금지** — 키인지 더미값인지 모호하면 단정하지 말고 "확인 필요"로 리포트하고 개발자에게 질문.
- [ ] **시각적·브라우저 검증은 사용자가 수행한다.** 암호화 적용 후 게임 기동 확인은 로직·로그 검증까지만 직접 한다.

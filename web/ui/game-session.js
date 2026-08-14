// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 게임 세션 매니저 — 아웃게임(ui-editor 씬)과 인게임 카트리지(플레이 모듈)의 표준 경계.
//
// 카트리지 계약(생명주기 인터페이스 — 인게임은 이 메서드들을 전부 구현해야 한다):
//   export default function createCartridge() → {
//     mount(el, session),            // 게임필드 div 장착. session = { v, post(type, payload) }
//     initialize(stageData),         // 스테이지 정보(맵·목표·제한 턴·기믹 등)로 초기화. Promise 반환 가능(완료 = 시작 준비됨)
//     startGame(),                   // 플레이 시작 (터치 활성화, 타이머 시작 등)
//     pauseGame(reason),             // 아웃게임 팝업(설정·일시정지 등) 시 연출·타이머 정지
//     resumeGame(),                  // 재개
//     forceQuit(reason),             // 강제 종료·이탈 시 인게임 리소스 정리
//     unmount(),                     // DOM 분리 정리(멱등)
//     onMessage(topic, payload)?,    // 선택 — 호스트 자유 메시지(설정 변경·구매 결과 등) 수신. 미구현이면 message() 가 경고 후 무시
//   }
//   - 카트리지 금지: 컨테이너 밖 DOM / localStorage·쿠키 / window 전역 오염 / scene-renderer 직접 접근.
// 카트리지 → 호스트 통신은 session.post 의 JSON 직렬화 가능 payload만 — iframe/postMessage 전환 대비.
// 상세 스펙: .claude/skills/ui-editor-ingame/SKILL.md (카트리지 측) · ui-editor-game/SKILL.md (호스트 측)

export const PROTOCOL_VERSION = 1;

// ── Authority(권위) 계약 — 재화·진행도·세션 결과의 최종 판정자 경계 ──────────────
// ui-editor는 이 계약만 정의하고 특정 게임의 서버를 알지 못한다(범용 에디터 룰).
// 기본값 LOCAL_AUTHORITY(전부 즉시 승인)는 클라이언트 신뢰 모델 — localStorage 값은 표시용이며 변조 방어가 없다.
// 리더보드·경쟁 이벤트·실물 보상 등 "경쟁 표면"이 있는 게임은 자기 서버로 approve(tx)를 구현해
// EconomyManager/ProgressManager/GameSession 생성자 옵션 `authority` 로 주입해야 한다. 미주입 상태의
// 재화·진행도를 경쟁 표면에 직접 쓰는 것은 프로토콜 위반이다(HMAC 등 클라이언트 서명은 계약에 없다 — 방어가 안 됨).
//
// 인터페이스: { approve(tx) → Promise<{ ok:boolean, ...권위값 }> }
//   - tx.op 는 AUTHORITY_OPS 중 하나. ok=false 면 매니저는 상태를 바꾸지 않는다(거부).
//   - 응답에 권위값이 있으면 매니저가 로컬 캐시를 그 값으로 덮어쓴다(서버 잔액이 진실, 로컬은 표시 캐시).
//     권위값을 생략하면 매니저의 로컬 규칙이 그대로 적용된다(LOCAL_AUTHORITY 경로).
//   - approve 가 throw 하면(네트워크 등) 그대로 호출자에게 전파된다 — 호스트가 재시도/안내를 결정한다.
//   op별 tx → 응답 권위값:
//     consumeHeart   { op, now }                         → { ok, hearts?, heartAnchorMs? }
//     grantHearts    { op, n, now, reason }              → { ok, hearts?, heartAnchorMs? }
//     grantCoins     { op, n, reason }                   → { ok, coins? }
//     spendCoins     { op, n, reason }                   → { ok, coins? }
//     commitProgress { op, stage, stars, score, ticket } → { ok, current? }
//     openSession    { op, stage }                       → { ok, ticket? }  // 티켓은 end 결과에 동봉 — 결과 위조 방어
export const AUTHORITY_OPS = ['consumeHeart', 'grantHearts', 'grantCoins', 'spendCoins', 'commitProgress', 'openSession'];

/** 기본 권위 — 전부 즉시 승인(로컬 규칙 그대로). 서버 없는 싱글플레이 게임용. */
export const LOCAL_AUTHORITY = Object.freeze({ approve: async () => ({ ok: true }) });

// Ingame 씬에서 카트리지가 마운트될 예약 레이어 이름.
// (lib/scene-guide.js 에도 같은 문자열이 있다 — 그쪽은 서버/SW 공유 UMD, 이쪽은 게임 배포 ESM이라 모듈 공유 불가. 변경 시 양쪽 동기화할 것.)
export const GAME_FIELD_LAYER_NAME = 'GameField';

// Ingame 씬 HUD 텍스트에 예약된 표준 bindingKey 어휘. 이 외 임의 키 추가 금지(필요 시 사용자에게 요청).
// 장르 특화 어휘 확장(예: RPG의 hp/mp)은 보류 — game-skill/README.md 의 보류 규칙 참조.
export const HUD_BINDING_KEYS = ['hud.score', 'hud.moves', 'hud.goal', 'hud.time', 'hud.combo', 'hud.stage'];

// 카트리지 hud payload 필드 → bindingKey 기본 매핑. GameSession 생성자 옵션 hudMap 으로 교체 가능.
export const DEFAULT_HUD_MAP = {
  score: 'hud.score',
  movesLeft: 'hud.moves',
  goal: 'hud.goal',
  timeLeft: 'hud.time',
  combo: 'hud.combo',
  stage: 'hud.stage',
};

// 카트리지가 반드시 구현해야 하는 생명주기 인터페이스. 장착 시점에 검사해 누락이면 즉시 실패한다.
// onMessage 는 목록에 없다(선택 구현) — 미구현 카트리지에도 message() 가 안전하게 무시된다.
export const CARTRIDGE_METHODS = ['mount', 'initialize', 'startGame', 'pauseGame', 'resumeGame', 'forceQuit', 'unmount'];

// 카트리지 → 호스트 이벤트 사전 — type → payload 필수 필드. 여기 없는 type 은 프로토콜 위반.
export const CARTRIDGE_EVENTS = {
  hud: [],                       // { score?, movesLeft?, goal?, timeLeft?, combo?, stage? } 부분 갱신 허용
  progress: [],                  // 자유 정의 직렬화 객체
  end: ['outcome', 'score'],     // { outcome: 'clear'|'fail'|'quit', score, stats? }
  error: ['message'],
};
export const END_OUTCOMES = ['clear', 'fail', 'quit'];

// 세션 상태 전이표. 호스트 GameSession 이 유일한 상태 보유자.
// mounted = mount 완료·initialize 진행 중, ready = initialize 완료(시작 대기).
export const ALLOWED_TRANSITIONS = {
  idle: ['loading', 'disposed'],
  loading: ['mounted', 'error', 'disposed'],
  mounted: ['ready', 'error', 'disposed'],
  ready: ['running', 'error', 'disposed'],
  running: ['paused', 'ended', 'error', 'disposed'],
  paused: ['running', 'ended', 'error', 'disposed'],
  ended: ['disposed'],
  error: ['disposed'],
  disposed: ['loading'], // 재시작(새 카트리지 인스턴스)
};

/** 카트리지 인스턴스가 생명주기 인터페이스를 전부 구현했는지 검사. 반환 { ok, missing }. */
export function validateCartridgeInterface(cartridge) {
  const missing = CARTRIDGE_METHODS.filter(m => typeof cartridge?.[m] !== 'function');
  return { ok: missing.length === 0, missing };
}

/** payload가 JSON 직렬화 가능한지 재귀 검사. 위반 시 throw — postMessage 전환 시에도 그대로 동작해야 하므로 상시 실행. */
export function assertSerializable(value, path = 'payload') {
  const t = typeof value;
  if (value === null || t === 'string' || t === 'boolean') return;
  if (t === 'number') {
    if (!Number.isFinite(value)) throw new Error(`[GameSession] ${path}: 비유한 숫자(${value})는 직렬화 불가`);
    return;
  }
  if (t === 'function' || t === 'symbol' || t === 'undefined' || t === 'bigint') {
    throw new Error(`[GameSession] ${path}: ${t} 은 JSON 직렬화 불가`);
  }
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertSerializable(v, `${path}[${i}]`));
    return;
  }
  if (typeof Node !== 'undefined' && value instanceof Node) {
    throw new Error(`[GameSession] ${path}: DOM 노드는 메시지에 실을 수 없음`);
  }
  const proto = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) {
    throw new Error(`[GameSession] ${path}: 클래스 인스턴스(${proto?.constructor?.name})는 직렬화 불가 — plain object 로 변환할 것`);
  }
  for (const [k, v] of Object.entries(value)) assertSerializable(v, `${path}.${k}`);
}

/** 카트리지 → 호스트 이벤트 메시지 검증. 반환 { ok, error? }. */
export function validateMessage(msg) {
  if (!msg || typeof msg !== 'object') return { ok: false, error: '메시지가 객체가 아님' };
  if (msg.v !== PROTOCOL_VERSION) return { ok: false, error: `프로토콜 버전 불일치: ${msg.v} (기대: ${PROTOCOL_VERSION})` };
  const required = CARTRIDGE_EVENTS[msg.type];
  if (!required) return { ok: false, error: `알 수 없는 type '${msg.type}'` };
  const payload = msg.payload || {};
  for (const field of required) {
    if (payload[field] === undefined) return { ok: false, error: `'${msg.type}' payload에 필수 필드 '${field}' 없음` };
  }
  if (msg.type === 'end' && !END_OUTCOMES.includes(payload.outcome)) {
    return { ok: false, error: `end.outcome '${payload.outcome}' — ${END_OUTCOMES.join('|')} 만 허용` };
  }
  return { ok: true };
}

/** hud payload → renderer.update() 용 중첩 바인딩 데이터. 매핑에 없는 키는 경고 후 무시(임의 키 금지). */
export function hudToBindingData(hud, hudMap = DEFAULT_HUD_MAP) {
  const out = {};
  for (const [field, value] of Object.entries(hud || {})) {
    const bindingKey = hudMap[field];
    if (!bindingKey) {
      console.warn(`[GameSession] hud 필드 '${field}' 는 hudMap에 없어 무시됨 — 표준 어휘(${Object.keys(hudMap).join(', ')}) 사용`);
      continue;
    }
    let node = out;
    const parts = bindingKey.split('.');
    parts.slice(0, -1).forEach(p => { node = node[p] = node[p] || {}; });
    node[parts[parts.length - 1]] = value;
  }
  return out;
}

export class GameSession {
  /**
   * @param {object} opts
   * @param {SceneRenderer} opts.renderer - GameField 레이어를 가진 Ingame 씬의 renderer (show() 완료 상태)
   * @param {string} [opts.mountLayerName] - 마운트 지점 레이어 이름 (기본 'GameField')
   * @param {object} [opts.hudMap] - hud payload 필드 → bindingKey 매핑 (기본 DEFAULT_HUD_MAP)
   * @param {number} [opts.initTimeoutMs] - initialize() 완료 대기 한도 (기본 10000)
   * @param {object} [opts.authority] - Authority 계약 구현체 (기본 LOCAL_AUTHORITY — 파일 상단 계약 주석 참조)
   */
  constructor({ renderer, mountLayerName = GAME_FIELD_LAYER_NAME, hudMap = DEFAULT_HUD_MAP, initTimeoutMs = 10000, authority = null } = {}) {
    if (!renderer) throw new Error('[GameSession] renderer 필수');
    this._renderer = renderer;
    this._mountLayerName = mountLayerName;
    this._hudMap = hudMap;
    this._initTimeoutMs = initTimeoutMs;
    this._state = 'idle';
    this._cartridge = null;
    this._hostEl = null;
    this._callbacks = {};
    this._authority = authority || LOCAL_AUTHORITY;
    this._ticket = null;              // openSession 승인 티켓 — end 결과에 동봉(로컬 권위면 null)
  }

  get state() { return this._state; }
  get isActive() { return !['idle', 'ended', 'error', 'disposed'].includes(this._state); }
  get ticket() { return this._ticket; }

  /**
   * 카트리지 로드→인터페이스 검사→mount→initialize(stageData). 완료(ready) 후 startGame() 으로 플레이 개시.
   * @param {string|Function} cartridge - 모듈 URL(dynamic import) 또는 createCartridge 팩토리 함수
   * @param {object} [opts] - { stage, seed, config, onEnd, onProgress, onError, onHud }
   *   stageData = { stage, seed, config } 로 initialize 에 전달. config = 맵 구조·목표·제한 턴·기믹 등 게임별 자유 정의(직렬화 가능)
   */
  async start(cartridge, { stage = null, seed = null, config = {}, onEnd = null, onProgress = null, onError = null, onHud = null } = {}) {
    if (this.isActive) { console.warn(`[GameSession] start 무시 — 세션이 이미 활성(${this._state}). 동시 세션은 1개`); return this; }
    if (this._state === 'ended' || this._state === 'error') this.dispose();
    this._callbacks = { onEnd, onProgress, onError, onHud };
    this._setState('loading');
    try {
      // 권위 승인 — 서버 권위 게임은 여기서 세션 티켓을 발급받는다(거부 = 시작 실패, 서버가 스테이지 잠금 등을 판정).
      const auth = await this._authority.approve({ op: 'openSession', stage });
      if (!auth || auth.ok !== true) throw new Error(`권위(authority)가 세션 시작을 거부함 — stage ${stage}`);
      this._ticket = auth.ticket ?? null;
      if (this._ticket != null) assertSerializable(this._ticket, 'openSession.ticket');

      let factory = cartridge;
      if (typeof cartridge === 'string') factory = (await import(cartridge)).default;
      if (this._state !== 'loading') {
        // import 대기 중 abort()/dispose() 됨 — 여기서 계속하면 disposed 상태로 mount 가 일어나는 좀비 세션이 된다.
        console.warn(`[GameSession] start 중단 — 카트리지 로드 중 세션이 정리됨(${this._state})`);
        return this;
      }
      if (typeof factory !== 'function') throw new Error('카트리지 모듈에 default export 함수(createCartridge)가 없음');

      const instance = factory();
      const iface = validateCartridgeInterface(instance);
      if (!iface.ok) throw new Error(`카트리지가 생명주기 인터페이스를 구현하지 않음 — 누락: ${iface.missing.join(', ')} (ui-editor-ingame 스킬 참조)`);

      const wrap = this._renderer.getElementByName(this._mountLayerName);
      if (!wrap) throw new Error(`'${this._mountLayerName}' 레이어 없음 — Ingame 씬에 '${this._mountLayerName}' 이름의 레이어를 추가하고 재publish 하세요`);

      const host = document.createElement('div');
      host.className = 'sr-game-host';
      host.style.cssText = 'position:absolute;inset:0;overflow:hidden;';
      wrap.appendChild(host);
      this._hostEl = host;

      const session = {
        v: PROTOCOL_VERSION,
        post: (type, payload = {}) => this._receiveFromCartridge(type, payload),
      };

      this._cartridge = instance;
      instance.mount(host, session);
      this._setState('mounted');

      const stageData = { stage, seed, config };
      const initOk = await this._callCartridge('initialize', [stageData], this._initTimeoutMs);
      if (initOk && this._state === 'mounted') this._setState('ready');
    } catch (err) {
      this._fail(err);
    }
    return this;
  }

  /** ready 상태에서 플레이 개시 (예: pop_LevelStart 닫힌 뒤 호출). */
  startGame() {
    if (this._state !== 'ready') { console.warn(`[GameSession] startGame 무시 — ready 상태가 아님(${this._state})`); return; }
    this._setState('running');
    this._callCartridge('startGame', []);
  }

  pause(reason = 'user') {
    if (this._state !== 'running') { console.warn(`[GameSession] pause 무시 — running 상태가 아님(${this._state})`); return; }
    this._setState('paused');
    this._callCartridge('pauseGame', [reason]);
  }

  resume() {
    if (this._state !== 'paused') { console.warn(`[GameSession] resume 무시 — paused 상태가 아님(${this._state})`); return; }
    this._setState('running');
    this._callCartridge('resumeGame', []);
  }

  /**
   * 카트리지에 자유 메시지 전달(선택 확장) — 설정 변경·구매 결과 등 호스트→게임 통지.
   * 카트리지가 onMessage(topic, payload) 를 구현한 경우에만 전달된다(미구현 = 경고 후 무시).
   * @returns {Promise<boolean>|false} 전달 성공 여부 — 카트리지 예외는 공통 경로(_callCartridge)가 _fail 처리
   */
  message(topic, payload = {}) {
    if (!this.isActive || !this._cartridge) { console.warn(`[GameSession] message 무시 — 활성 세션 없음(${this._state})`); return false; }
    if (typeof this._cartridge.onMessage !== 'function') { console.warn(`[GameSession] message 무시 — 카트리지가 onMessage 미구현(topic '${topic}')`); return false; }
    return this._callCartridge('onMessage', [topic, payload]);
  }

  /** 세션 강제 종료 — forceQuit(리소스 정리 기회) 후 강제 정리. 카트리지가 어떤 상태여도 아웃게임은 살아남는다. */
  abort(reason = 'quit') {
    if (this._state === 'idle' || this._state === 'disposed') return;
    if (this._cartridge) {
      try {
        assertSerializable(reason, 'forceQuit.reason');
        console.log('[GameSession] →cartridge forceQuit', reason);
        this._cartridge.forceQuit(reason);
      } catch (e) { console.error('[GameSession] forceQuit 예외(강제 정리로 계속):', e); }
    }
    this._teardown();
  }

  dispose() { this._teardown(); }

  // ── 내부 ──────────────────────────────────────────────────────────────────

  _setState(next) {
    const allowed = ALLOWED_TRANSITIONS[this._state] || [];
    if (!allowed.includes(next)) { console.warn(`[GameSession] 전이표 위반 무시: ${this._state} → ${next}`); return false; }
    console.log(`[GameSession] state: ${this._state} → ${next}`);
    this._state = next;
    return true;
  }

  /** 카트리지 생명주기 메서드 호출 — 인자 직렬화 검사 + 예외 격리(+선택 타임아웃). 실패 시 _fail 처리 후 false 반환(재throw 없음 — 비대기 호출 경로의 unhandled rejection 방지). */
  async _callCartridge(method, args, timeoutMs = 0) {
    try {
      args.forEach((a, i) => assertSerializable(a, `${method}.args[${i}]`));
      console.log(`[GameSession] →cartridge ${method}`, ...args);
      const result = this._cartridge[method](...args);
      if (result && typeof result.then === 'function') {
        if (timeoutMs > 0) {
          await Promise.race([
            result,
            new Promise((_, rej) => setTimeout(() => rej(new Error(`${method} 타임아웃(${timeoutMs}ms) — 카트리지가 완료하지 않음`)), timeoutMs)),
          ]);
        } else {
          await result;
        }
      }
      return true;
    } catch (err) {
      this._fail(err);
      return false;
    }
  }

  _receiveFromCartridge(type, payload) {
    const msg = { v: PROTOCOL_VERSION, type, payload };
    const check = validateMessage(msg);
    if (!check.ok) { console.warn(`[GameSession] 수신 차단: ${check.error}`); return; }
    assertSerializable(payload);
    console.log('[GameSession] ←cartridge', type, payload);

    if (type === 'hud') {
      if (!this.isActive) return;
      this._renderer.update(hudToBindingData(payload, this._hudMap));
      this._safeCallback('onHud', payload);
    } else if (type === 'progress') {
      if (!this.isActive) return;
      this._safeCallback('onProgress', payload);
    } else if (type === 'end') {
      if (this._state !== 'running' && this._state !== 'paused') { console.warn(`[GameSession] end 무시 — 플레이 중이 아님(${this._state})`); return; }
      this._setState('ended');
      // 티켓 동봉 — 호스트는 이 티켓을 recordClear/보상 grant 에 그대로 넘겨 권위가 결과를 검증하게 한다.
      this._safeCallback('onEnd', this._ticket == null ? payload : { ...payload, ticket: this._ticket });
      this._teardown(); // 결과 통지 후 자동 정리 — 재도전은 start() 재호출(새 인스턴스)
    } else if (type === 'error') {
      this._fail(new Error(`카트리지 오류 보고: ${payload.message}`));
    }
  }

  _safeCallback(name, payload) {
    const fn = this._callbacks[name];
    if (!fn) return;
    try { fn(payload); } catch (err) { console.error(`[GameSession] ${name} 콜백 예외:`, err); }
  }

  /** 카트리지發 실패 — 오류 로그·onError 후 강제 정리. 원인 판정을 위해 오류를 삼키지 않고 그대로 로그한다. */
  _fail(err) {
    if (this._state === 'disposed') return; // 정리 경합 시 1회만 처리
    console.error('[GameSession] 실패:', err);
    this._setState('error');
    this._safeCallback('onError', { message: err?.message || String(err) });
    this._teardown();
  }

  /** 정리(멱등) — 카트리지 협조 없이도 sr-game-host 제거로 아웃게임 복구를 보장한다. */
  _teardown() {
    if (this._state === 'disposed') return;
    if (this._cartridge) {
      try { this._cartridge.unmount(); } catch (err) { console.error('[GameSession] unmount 예외(강제 제거로 계속):', err); }
      this._cartridge = null;
    }
    if (this._hostEl?.parentNode) this._hostEl.parentNode.removeChild(this._hostEl);
    this._hostEl = null;
    this._setState('disposed');
  }
}

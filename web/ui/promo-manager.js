// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 프로모 매니저 v2 — 이벤트/상품 레지스트리(promo-registry.json, ui-editor 어드민에서 편집)를 읽어
//  1) 로비 도크(EventDock/ProductDock 예약 오브젝트)를 아이콘으로 채우고
//  2) 서프라이즈 항목을 fire(triggerKey) 한 줄로 열고
//  3) 기간(스케줄)·노출 조건을 매니저가 판정한다.
//
// 소유권 규칙:
//  - 기간·조건 판정 = 매니저 소관. 게임은 판정 재료만 공급: setContext({ level, loseStreak, ... })
//    (공급할 키 목록은 publish 폴더 PROMO.md 참조). setFlags({노출키:bool}) 는 수동 override 레인으로 유지.
//  - 반복(매일/매주) 판정 시계 = 게임 기기 로컬. 절대 시각(start/end)은 ISO 오프셋 포함이라 어디서든 동일.
//  - 구매 실행 = 매니저 밖. 게임이 Authority/EconomyManager 로 지불하고, 성공 시 recordPurchase(id) 로 보고.
//    구매제한 카운터는 localStorage 표시 캐시일 뿐 — 유료 한도의 실제 강제는 게임 서버(Authority) 몫.
//  - 씬 진입: pop_* = 주입받은 PopupManager, 일반 씬 = 'promo:navigate' 이벤트로 게임에 위임(전환 시퀀스는 게임 소유).
//
// ── PromoSource 규약(정본) — 레지스트리를 게임 서버에서 서빙(라이브옵스)하려는 게임용 ─────────────
//  주입: new PromoManager({ source }) . 미주입 시 StaticPromoSource(번들 파일) — publish 기반 정적 모델.
//  인터페이스:
//    PromoSource = {
//      fetchRegistry(): Promise<{ registry: object, serverNowMs?: number }>,
//      now?(): number   // epochMs — 제공 시 이 시계가 스케줄 판정의 진실(최우선)
//    }
//  서버 엔드포인트 규약:
//    - publish 산출물 promo-registry.json 형식({ version, conditionKeys, entries }) "그대로" 서빙한다.
//      변환 계층 금지 — 어드민이 만든 파일이 곧 와이어 포맷.
//    - ETag/Cache-Control 권장. 서버 시각은 HTTP Date 응답 헤더(200·304 모두 존재)에서 취득해
//      serverNowMs 로 반환 — 매니저가 clockOffset 을 계산해 기기 시계 조작을 무력화한다.
//    - registry.version > PROMO_REGISTRY_VERSION 이면 매니저가 번들 사본으로 폴백(하위 리더 보호).
//      미지 필드는 무시된다(전방호환) — 필드 추가만으로는 version 을 올리지 말 것.
//    - 레지스트리는 클라이언트 공개 데이터 — 비밀 금지. 가격 "표시"는 레지스트리, 가격 "강제"는 Authority.
//    - fetchRegistry 실패 시 매니저가 번들 promo-registry.json 으로 자동 폴백(오프라인 내성).
//  참고 구현(게임 코드에 복사):
//    const source = {
//      async fetchRegistry() {
//        const r = await fetch('https://game.example.com/live/promo-registry.json');
//        if (!r.ok) throw new Error('promo source HTTP ' + r.status);
//        return { registry: await r.json(), serverNowMs: Date.parse(r.headers.get('Date')) || undefined };
//      },
//    };

// 도크 컨테이너 예약 레이어 이름.
// (lib/scene-guide.js 의 PROMO_DOCK_LAYER_NAMES 와 같은 값 — 그쪽은 서버/SW 공유 UMD라 모듈 공유 불가. 변경 시 양쪽 동기화할 것.)
export const PROMO_DOCK_LAYER_NAMES = { event: 'EventDock', product: 'ProductDock' };
export const PROMO_REGISTRY_VERSION = 2;

// ═══ 순수 평가기 — DOM/Date.now() 미사용(nowMs 파라미터), node 단독 테스트 가능 ═══════════════

// v1/v2 혼재 entry → canonical(평탄 v2) 정규화. 다운스트림은 canonical 만 본다.
export function normalizeRegistryEntry(raw) {
  const e = Object.assign({}, raw);
  if (typeof e.priority !== 'number') e.priority = 0;
  if (typeof e.group !== 'string') e.group = '';
  if (e.schedule === undefined) e.schedule = null;
  if (!Array.isArray(e.conditions)) e.conditions = [];
  if (e.commerce === undefined) e.commerce = null;
  if (e.enabled === undefined) e.enabled = true;
  return e;
}

function _parseTs(iso, fallback) {
  if (!iso) return fallback;
  const t = Date.parse(iso);
  return isNaN(t) ? fallback : t;
}
function _parseHM(s) { // 'HH:MM' → 로컬 자정 기준 ms
  const m = /^(\d{1,2}):(\d{2})$/.exec(s || '');
  return m ? ((+m[1]) * 60 + (+m[2])) * 60000 : null;
}
const DAY_MS = 86400000;

// 스케줄 판정: { status:'upcoming'|'live'|'ended', nextChangeMs:number|null }
// null 스케줄 = 상시 live. 반복(daily/weekly)의 요일·시간대는 기기 로컬 기준.
// nextChangeMs = 다음 재평가 시점(보수적 경계 — 전환을 놓치지 않되, 자정 등 변화 없는 지점이 낄 수 있다.
// 타이머가 그 시점에 재평가만 하면 되므로 무해). 없으면 null.
export function evaluateSchedule(schedule, nowMs) {
  if (!schedule) return { status: 'live', nextChangeMs: null };
  const start = _parseTs(schedule.start, -Infinity);
  const end = _parseTs(schedule.end, Infinity);
  if (nowMs < start) return { status: 'upcoming', nextChangeMs: start };
  if (nowMs >= end) return { status: 'ended', nextChangeMs: null };

  const endBoundary = isFinite(end) ? end : null;
  const rec = schedule.recurrence;
  const win = rec && rec.window ? { from: _parseHM(rec.window.from), to: _parseHM(rec.window.to) } : null;
  const type = rec && rec.type;
  if (!rec || type === 'none' || (type === 'daily' && (!win || win.from == null || win.to == null))) {
    return { status: 'live', nextChangeMs: endBoundary }; // daily 인데 window 불량 = 상시(린트가 잡음)
  }

  const d = new Date(nowMs);
  const midnight = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const inDay = nowMs - midnight;
  const days = type === 'weekly' ? (Array.isArray(rec.days) ? rec.days : []) : null;
  const dayOk = days ? days.indexOf(d.getDay()) !== -1 : true;

  let winOk = true;
  if (win && win.from != null && win.to != null) {
    winOk = win.from <= win.to
      ? (inDay >= win.from && inDay < win.to)          // 같은 날 안의 시간대
      : (inDay >= win.from || inDay < win.to);          // 자정 걸침(예: 22:00~02:00)
  }
  const live = dayOk && winOk;

  // 다음 경계 후보: 오늘의 window 열림/닫힘, 다음 자정(요일 전환), 겉봉투 end — nowMs 보다 큰 것 중 최소
  const candidates = [midnight + DAY_MS];
  if (win && win.from != null && win.to != null) {
    candidates.push(midnight + win.from, midnight + win.from + DAY_MS);
    candidates.push(win.from <= win.to ? midnight + win.to : midnight + win.to + DAY_MS, midnight + win.to);
  }
  if (endBoundary != null) candidates.push(endBoundary);
  const next = candidates.filter((t) => t > nowMs).sort((a, b) => a - b)[0];

  return { status: live ? 'live' : 'upcoming', nextChangeMs: next != null ? Math.min(next, end) : endBoundary };
}

function _looseEq(a, b) {
  const na = Number(a), nb = Number(b);
  if (a !== '' && b !== '' && a != null && b != null && isFinite(na) && isFinite(nb)) return na === nb;
  return String(a) === String(b);
}
function _applyOp(actual, op, value) {
  switch (op) {
    case 'in': return Array.isArray(value) && value.some((v) => _looseEq(actual, v));
    case '==': return _looseEq(actual, value);
    case '!=': return !_looseEq(actual, value);
    case '>=': case '<=': case '>': case '<': {
      const na = Number(actual), nv = Number(value);
      if (!isFinite(na) || !isFinite(nv)) return false; // 순서 비교는 숫자만 — 비숫자는 결정적으로 fail
      return op === '>=' ? na >= nv : op === '<=' ? na <= nv : op === '>' ? na > nv : na < nv;
    }
    default: return false;
  }
}

// 조건 판정(AND 결합): { pass, missing:[미공급 컨텍스트 키...] }
export function evaluateConditions(conditions, context) {
  const ctx = context || {};
  const missing = [];
  let pass = true;
  (conditions || []).forEach((c) => {
    if (!c || !c.key) return;
    if (!(c.key in ctx)) { missing.push(c.key); pass = false; return; }
    if (!_applyOp(ctx[c.key], c.op, c.value)) pass = false;
  });
  return { pass, missing };
}

// 항목 종합 판정: visible = enabled ∧ 스케줄 live ∧ 조건 pass ∧ (노출키 없음 ∨ flag on) ∧ (once 한도 소진 아님)
// v1 항목(schedule/conditions 없음)은 기존 동작과 완전 동치.
export function evaluateEntry(entry, { nowMs, context = {}, flags = {}, purchasable = true } = {}) {
  if (entry.enabled === false) return { visible: false, status: 'disabled', blockedBy: 'disabled', missing: [], nextChangeMs: null };
  const sch = evaluateSchedule(entry.schedule, nowMs);
  if (sch.status !== 'live') return { visible: false, status: sch.status, blockedBy: 'schedule', missing: [], nextChangeMs: sch.nextChangeMs };
  const cond = evaluateConditions(entry.conditions, context);
  if (!cond.pass) return { visible: false, status: 'live', blockedBy: 'conditions', missing: cond.missing, nextChangeMs: sch.nextChangeMs };
  if (entry.exposeKey && !flags[entry.exposeKey]) return { visible: false, status: 'live', blockedBy: 'flag', missing: [], nextChangeMs: sch.nextChangeMs };
  const limit = entry.commerce && entry.commerce.purchaseLimit;
  if (!purchasable && limit && limit.scope === 'once') {
    return { visible: false, status: 'live', blockedBy: 'purchased', missing: [], nextChangeMs: sch.nextChangeMs };
  }
  return { visible: true, status: 'live', blockedBy: null, missing: [], nextChangeMs: sch.nextChangeMs };
}

// 구매제한 카운터의 스코프 키(기기 로컬 기준 리셋): once→'total', daily→'d:YYYY-MM-DD', weekly→'w:YYYY-Www'(ISO 주)
export function purchaseScopeKey(scope, nowMs) {
  const d = new Date(nowMs);
  const pad = (n) => String(n).padStart(2, '0');
  if (scope === 'daily') return 'd:' + d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  if (scope === 'weekly') {
    // ISO 8601 주차(목요일 기준)
    const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7));
    const week1 = new Date(t.getFullYear(), 0, 4);
    const week = 1 + Math.round(((t - week1) / DAY_MS - 3 + ((week1.getDay() + 6) % 7)) / 7);
    return 'w:' + t.getFullYear() + '-W' + pad(week);
  }
  return 'total';
}

// ═══ 기본 소스 — publish 번들의 정적 파일(현재의 유일한 배포 채널) ═══════════════════════════

export class StaticPromoSource {
  constructor({ publishPath = '' } = {}) { this._publishPath = publishPath; }
  async fetchRegistry() {
    const r = await fetch(this._publishPath + 'promo-registry.json');
    if (!r.ok) throw new Error(`PromoSource: promo-registry.json 로드 실패(HTTP ${r.status})`);
    return { registry: await r.json() };
  }
}

// ═══ 매니저 ═══════════════════════════════════════════════════════════════════════════════

export class PromoManager {
  /**
   * @param {object} [opts]
   * @param {string} [opts.basePath] - 아이콘 등 에셋 경로 prefix (SceneRenderer 의 basePath 와 같은 값)
   * @param {string} [opts.publishPath] - promo-registry.json·scenes-index.json·contract 가 있는 publish 폴더 prefix
   * @param {import('./popup-manager.js').PopupManager} [opts.popupManager] - pop_* 항목을 열 때 사용
   * @param {number} [opts.dockGap] - 도크 아이콘 세로 간격(px)
   * @param {object} [opts.source] - PromoSource(상단 규약) — 미주입 시 번들 정적 파일
   * @param {string} [opts.storagePrefix] - 구매제한 카운터 localStorage prefix (Economy/Sound 와 같은 게임 프리픽스)
   */
  constructor({ basePath = '', publishPath = '', popupManager = null, dockGap = 12, source = null, storagePrefix = '' } = {}) {
    this._basePath = basePath;
    this._publishPath = publishPath;
    this._popups = popupManager;
    this._dockGap = dockGap;
    this._source = source || new StaticPromoSource({ publishPath });
    this._sourceIsStatic = !source;
    this._storageKey = storagePrefix + 'promo_v1';
    this._clockOffsetMs = 0;
    this._entries = [];        // canonical entries
    this._index = null;        // scenes-index.json
    this._flags = {};          // 수동 override 노출키 (진실은 게임)
    this._context = {};        // 조건 판정 재료 (setContext 로 공급)
    this._renderer = null;
    this._hosts = {};
    this._handlers = {};
    this._warnedKeys = {};     // 미공급 컨텍스트 키 경고 1회 제한
    this._timer = null;
    this._onVisibility = null;
    this._lastVisibleIds = null;
  }

  // 레지스트리(PromoSource) + scenes-index 로드. 소스 실패/버전 초과 시 번들 폴백(오프라인 내성).
  async load() {
    let reg = null;
    try {
      const res = await this._source.fetchRegistry();
      reg = res.registry;
      if (reg && reg.version > PROMO_REGISTRY_VERSION) {
        throw new Error(`registry version ${reg.version} > 지원 ${PROMO_REGISTRY_VERSION}`);
      }
      this._clockOffsetMs = (typeof res.serverNowMs === 'number') ? res.serverNowMs - Date.now() : 0;
    } catch (e) {
      if (this._sourceIsStatic) throw e; // 번들 자체가 없음 — 삼키지 않는다
      console.warn('[PromoManager] PromoSource 실패 — 번들 promo-registry.json 폴백:', e.message || e);
      reg = (await new StaticPromoSource({ publishPath: this._publishPath }).fetchRegistry()).registry;
      this._clockOffsetMs = 0;
    }
    this._entries = (Array.isArray(reg && reg.entries) ? reg.entries : []).map(normalizeRegistryEntry);
    const idxResp = await fetch(this._publishPath + 'scenes-index.json');
    if (!idxResp.ok) throw new Error(`PromoManager: scenes-index.json 로드 실패(HTTP ${idxResp.status})`);
    this._index = await idxResp.json();
    return this;
  }

  _now() {
    if (this._source && typeof this._source.now === 'function') return this._source.now();
    return Date.now() + this._clockOffsetMs;
  }

  /** 로비 renderer 의 도크 컨테이너(EventDock/ProductDock)를 찾아 아이콘을 채운다. show() 이후 호출. */
  attachDocks(renderer) {
    this._renderer = renderer;
    if (!this._onVisibility && typeof document !== 'undefined') {
      this._onVisibility = () => { if (!document.hidden && this._renderer) this._renderDocks(); };
      document.addEventListener('visibilitychange', this._onVisibility);
    }
    this._renderDocks();
    return this;
  }

  /** 도크 주입분·타이머·리스너 정리(씬 이탈 시). */
  detachDocks() {
    Object.values(this._hosts).forEach((h) => { if (h && h.parentNode) h.parentNode.removeChild(h); });
    this._hosts = {};
    this._renderer = null;
    this._lastVisibleIds = null;
    if (this._timer) { clearTimeout(this._timer); this._timer = null; }
    if (this._onVisibility) { document.removeEventListener('visibilitychange', this._onVisibility); this._onVisibility = null; }
  }

  /** 수동 노출키 에코(override 레인) — v1 호환. 병합 후 재평가·재렌더. */
  setFlags(flags) {
    Object.assign(this._flags, flags || {});
    if (this._renderer) this._renderDocks();
    return this;
  }

  /** 조건 판정 재료 공급 — 공급할 키 목록은 PROMO.md 참조. 병합 후 재평가·재렌더. */
  setContext(ctx) {
    Object.assign(this._context, ctx || {});
    if (this._renderer) this._renderDocks();
    return this;
  }

  getContext() { return Object.assign({}, this._context); }

  _evaluate(entry, nowMs) {
    const ev = evaluateEntry(entry, {
      nowMs, context: this._context, flags: this._flags, purchasable: this.isPurchasable(entry.id, nowMs),
    });
    ev.missing.forEach((k) => {
      if (this._warnedKeys[k]) return;
      this._warnedKeys[k] = 1;
      console.warn('[PromoManager] 조건 키가 setContext 로 공급되지 않았습니다:', k, '— PROMO.md 의 컨텍스트 키 표 참조');
    });
    return ev;
  }

  _entryRuntime(entry, nowMs) {
    const ev = this._evaluate(entry, nowMs);
    const end = entry.schedule ? _parseTs(entry.schedule.end, Infinity) : Infinity;
    return {
      status: ev.status, visible: ev.visible, blockedBy: ev.blockedBy,
      remainingMs: (ev.status !== 'ended' && isFinite(end)) ? Math.max(0, end - nowMs) : null,
      purchasable: this.isPurchasable(entry.id, nowMs),
      purchasedCount: this._purchasedCount(entry, nowMs),
      nextChangeMs: ev.nextChangeMs,
    };
  }

  /** 항목 조회(사본+runtime 판정 첨부) — 내부 entry 는 밖으로 새지 않는다. */
  getEntries(filter = {}) {
    const nowMs = this._now();
    return this._entries
      .filter((e) => (!filter.kind || e.kind === filter.kind) && (!filter.surface || e.surface === filter.surface))
      .map((e) => Object.assign({}, e, { runtime: this._entryRuntime(e, nowMs) }))
      .filter((e) => !filter.visibleOnly || e.runtime.visible);
  }

  getEntry(id) {
    const e = this._entries.find((x) => x.id === id);
    return e ? Object.assign({}, e, { runtime: this._entryRuntime(e, this._now()) }) : null;
  }

  /**
   * 서프라이즈 항목 열기 — 게임 판정 지점에서 호출. 기간·조건·구매가능을 매니저가 재검증하므로
   * 무조건 호출해도 안전(막히면 이유를 info 로 남기고 null).
   */
  async fire(triggerKey) {
    const nowMs = this._now();
    const entry = this._entries.find((e) => e.surface === 'triggered' && e.triggerKey === triggerKey);
    if (!entry) {
      console.warn('[PromoManager] fire 무시 — 레지스트리에 없는 triggerKey:', triggerKey);
      return null;
    }
    const ev = this._evaluate(entry, nowMs);
    if (!ev.visible && ev.blockedBy !== 'flag') { // triggered 는 노출키 무관 — flag 차단만 예외로 통과
      console.info('[PromoManager] fire 차단 —', triggerKey, '사유:', ev.blockedBy);
      return null;
    }
    if (!this.isPurchasable(entry.id, nowMs)) {
      console.info('[PromoManager] fire 차단 —', triggerKey, '사유: purchase-limit');
      return null;
    }
    await this._openEntry(entry, 'fire');
    return Object.assign({}, entry, { runtime: this._entryRuntime(entry, nowMs) });
  }

  // ── 구매제한 카운터(표시 캐시 — 유료 강제는 Authority 몫) ──────────────────────────────
  _loadPurchases() {
    try { return JSON.parse(localStorage.getItem(this._storageKey)) || { purchases: {} }; }
    catch (e) { return { purchases: {} }; }
  }
  _purchasedCount(entry, nowMs) {
    const limit = entry.commerce && entry.commerce.purchaseLimit;
    const scope = limit ? limit.scope : 'once';
    const rec = this._loadPurchases().purchases[entry.id] || {};
    return rec[purchaseScopeKey(scope, nowMs)] || 0;
  }
  /** 구매 성공 보고 — 게임이 Authority/Economy 지불 성공 "후" 호출. 카운터 영속 + 재렌더. */
  recordPurchase(id) {
    const entry = this._entries.find((x) => x.id === id);
    if (!entry) { console.warn('[PromoManager] recordPurchase 무시 — 없는 id:', id); return; }
    const nowMs = this._now();
    const limit = entry.commerce && entry.commerce.purchaseLimit;
    const key = purchaseScopeKey(limit ? limit.scope : 'once', nowMs);
    const data = this._loadPurchases();
    const rec = data.purchases[id] = data.purchases[id] || {};
    rec[key] = (rec[key] || 0) + 1;
    try { localStorage.setItem(this._storageKey, JSON.stringify(data)); }
    catch (e) { console.warn('[PromoManager] 구매 카운터 저장 실패', e); }
    if (this._renderer) this._renderDocks();
  }
  isPurchasable(id, nowMs) {
    const entry = this._entries.find((x) => x.id === id);
    if (!entry) return false;
    const limit = entry.commerce && entry.commerce.purchaseLimit;
    if (!limit) return true;
    return this._purchasedCount(entry, nowMs != null ? nowMs : this._now()) < limit.count;
  }

  /** 이벤트 구독('promo:navigate'|'promo:open'|'promo:schedule-change'). 반환값 = 구독 해제 함수. */
  on(eventName, fn) {
    (this._handlers[eventName] = this._handlers[eventName] || []).push(fn);
    return () => {
      this._handlers[eventName] = (this._handlers[eventName] || []).filter((f) => f !== fn);
    };
  }

  _emit(eventName, payload) {
    (this._handlers[eventName] || []).forEach((fn) => fn(payload));
  }

  // uuid 우선, 이름 fallback (scenes-index 해석 규약)
  _resolveScene(entry) {
    const scenes = (this._index && this._index.scenes) || [];
    return scenes.find((s) => entry.sceneUuid && s.uuid === entry.sceneUuid)
        || scenes.find((s) => entry.sceneName && s.name === entry.sceneName)
        || null;
  }

  async _openEntry(entry, via) {
    const hit = this._resolveScene(entry);
    if (!hit) {
      console.warn('[PromoManager] 대상 씬 해석 실패 — publish 목록에 없습니다:', entry.id, entry.sceneName || entry.sceneUuid);
      return;
    }
    const contractUrl = this._publishPath + hit.contract;
    const payload = {
      entry: Object.assign({}, entry, { runtime: this._entryRuntime(entry, this._now()) }),
      sceneName: hit.name, sceneUuid: hit.uuid, contractUrl, via,
    };
    this._emit('promo:open', payload); // 게임이 entry.commerce 를 씬 바인딩에 주입하는 지점
    if (hit.name.startsWith('pop_')) {
      if (!this._popups) {
        console.warn('[PromoManager] pop_ 항목인데 popupManager 미주입 — 생성자 옵션으로 PopupManager 를 넘기세요:', entry.id);
        return;
      }
      await this._popups.open(contractUrl);
      return;
    }
    // 일반 씬 = 씬 전환 — 시퀀스(playTransition·이력 스택)는 게임 소유라 이벤트로 위임
    this._emit('promo:navigate', payload);
  }

  _renderDocks() {
    const nowMs = this._now();
    const evalMap = {};   // id → evaluate 결과 (타이머·diff 용, 전 항목)
    this._entries.forEach((e) => { evalMap[e.id] = this._evaluate(e, nowMs); });

    Object.keys(PROMO_DOCK_LAYER_NAMES).forEach((kind) => {
      const dockName = PROMO_DOCK_LAYER_NAMES[kind];
      const items = this._entries
        .filter((e) => e.kind === kind && e.surface === 'dock' && evalMap[e.id].visible)
        .sort((a, b) => (b.priority - a.priority) || ((a.order || 0) - (b.order || 0)) || String(a.id).localeCompare(String(b.id)));

      const prev = this._hosts[kind];
      if (prev && prev.parentNode) prev.parentNode.removeChild(prev);
      delete this._hosts[kind];

      const wrap = this._renderer.getElementByName(dockName);
      if (!wrap) {
        if (items.length) console.warn('[PromoManager] 도크 컨테이너 "' + dockName + '" 오브젝트가 씬에 없습니다 — 로비 씬에 예약 이름으로 배치하세요.');
        return;
      }

      const host = document.createElement('div');
      host.style.cssText = 'position:absolute;inset:0;display:flex;flex-direction:column;gap:' + this._dockGap + 'px;pointer-events:auto;';
      items.forEach((entry) => {
        const cell = document.createElement('div');
        cell.style.cssText = 'position:relative;width:100%;';
        cell.dataset.promoId = entry.id || '';
        cell.dataset.promoGroup = entry.group || '';
        const btn = document.createElement('img');
        btn.src = this._basePath + (entry.icon || '');
        btn.alt = entry.id || '';
        btn.style.cssText = 'width:100%;height:auto;display:block;cursor:pointer;-webkit-tap-highlight-color:transparent;';
        btn.addEventListener('click', () => { this._openEntry(entry, 'dock'); });
        cell.appendChild(btn);
        const badge = entry.commerce && entry.commerce.badge;
        if (badge && badge.text) {
          const chip = document.createElement('span');
          chip.textContent = badge.text;
          chip.style.cssText = 'position:absolute;top:-4px;right:-4px;padding:2px 6px;border-radius:8px;'
            + 'font-size:11px;font-weight:700;color:#fff;pointer-events:none;background:' + (badge.color || '#e05555') + ';';
          cell.appendChild(chip);
        }
        host.appendChild(cell);
      });
      wrap.appendChild(host);
      this._hosts[kind] = host;
    });

    // 가시 집합 diff → promo:schedule-change (최초 렌더는 통지 생략)
    const visibleIds = new Set(this._entries.filter((e) => evalMap[e.id].visible).map((e) => e.id));
    if (this._lastVisibleIds) {
      const entered = this._entries.filter((e) => visibleIds.has(e.id) && !this._lastVisibleIds.has(e.id));
      const exited = this._entries.filter((e) => !visibleIds.has(e.id) && this._lastVisibleIds.has(e.id));
      if (entered.length || exited.length) {
        this._emit('promo:schedule-change', {
          entered: entered.map((e) => Object.assign({}, e)), exited: exited.map((e) => Object.assign({}, e)),
        });
      }
    }
    this._lastVisibleIds = visibleIds;

    // 다음 스케줄 경계에 재평가 타이머 1개
    if (this._timer) { clearTimeout(this._timer); this._timer = null; }
    const nexts = this._entries.map((e) => evalMap[e.id].nextChangeMs).filter((t) => t != null && t > nowMs);
    if (nexts.length) {
      const delay = Math.min(Math.max(Math.min(...nexts) - nowMs, 1000), 2147483647);
      this._timer = setTimeout(() => { if (this._renderer) this._renderDocks(); }, delay);
    }
  }
}

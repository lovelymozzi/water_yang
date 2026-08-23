// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 흐름 드라이버 — scene-flow.json 이 기술하는 "UI끼리의 흐름"을 데이터 그대로 실행한다.
//   버튼 엣지 구독 · 전환효과(playTransition Out→In) · 팝업(pop_*/__close__) · 이력(__back__)
//   · nav 호스팅(toHostedBy) 진입 · nav:tabchange 재배선 · 매니저 표준 바인딩 attach 를 전담한다.
// 게임 접점(훅) 3종만 게임 코드가 공급한다:
//   ① defineCondition(key, fn)  — 흐름도 조건 분기(hasHearts 등)의 술어. start() 전에 등록.
//   ② on('scene:enter', fn)     — 씬 진입 통지. 인게임 카트리지 마운트·씬별 커스텀 로직의 접점.
//   ③ fire(label|씬이름) / goto(ref) — 트리거 없는 문서 엣지("게임오버 시" 등)를 게임 사건 시점에 발화.
// 규칙:
//   - 씬 해석은 scenes-index.json, uuid 우선·이름 fallback (SKILL.md §2 와 동일 규약).
//   - update() 는 항상 show() 전에 시드된다(플리커 방지) — 드라이버가 renderer 생성/표시 순서를 보장.
//   - 조건 키 미등록·시작 씬 미지정은 폴백으로 삼키지 않고 명확한 error 로 표면화한다.
//   - 매니저(economy/progress)는 게임이 생성해 주입한다(수치가 게임 기획) — 드라이버는 attach 만.
//   - 팝업은 동시에 1개(PopupManager 규약). 팝업에서 일반 씬으로 가는 엣지는 팝업을 닫고 전환한다.
import { SceneRenderer } from './scene-renderer.js';
import { PopupManager } from './popup-manager.js';

// publish 산출물 폴더(이 모듈 옆)가 scenes-index.json·scene-flow.json 의 기본 위치
const MODULE_BASE = (() => {
  try { return new URL('.', import.meta.url).href; } catch (e) { return ''; }
})();

const BACK = '__back__';
const CLOSE = '__close__';

export class FlowDriver {
  /**
   * @param {object} [opts]
   * @param {HTMLElement} [opts.mount=document.body] - 씬 renderer 마운트 지점 (body = 화면 맞춤 스케일)
   * @param {string} [opts.basePath=''] - SceneRenderer basePath (엔트리 html 기준 asset 경로 보정)
   * @param {string} [opts.dataPath] - scenes-index.json·scene-flow.json 폴더 (기본: 이 모듈 옆)
   * @param {object} [opts.managers] - { economy?, progress?, popups? } — attachRenderer 자동 연동 대상.
   *                                   popups 미주입 시 드라이버가 PopupManager 를 생성한다.
   */
  constructor({ mount = null, basePath = '', dataPath = null, managers = {} } = {}) {
    this._mount = mount || (typeof document !== 'undefined' ? document.body : null);
    this._base = dataPath != null ? dataPath : MODULE_BASE;
    if (this._base && !this._base.endsWith('/')) this._base += '/';
    this._rendererOpts = { basePath };
    this._managers = managers;
    this._popups = managers.popups || new PopupManager(this._rendererOpts);
    this._index = null;            // scenes-index.json
    this._flow = null;             // scene-flow.json
    this._conditions = {};         // 조건 키 → 술어
    this._handlers = {};           // 드라이버 이벤트('scene:enter') → Set<fn>
    this._renderers = new Map();   // sceneUuid → SceneRenderer (구독 유지 캐시 — hide 가 DOM 은 걷어준다)
    this._wired = new WeakSet();   // 엣지 구독을 마친 renderer — nav sub-renderer 는 매 마운트가 새 인스턴스라 WeakSet(GC 허용)
    this._history = [];            // 씬 uuid 이력 스택 (__back__ / back())
    this._current = null;          // { uuid, name, renderer } — nav 진입 시 renderer = nav 호스트
    this._dataBuffer = {};         // update() 누적 — 이후 생성되는 renderer 에도 show() 전 시드
    this._popupUuid = null;        // 열려 있는 팝업 씬 uuid
    this._popupRenderer = null;    // 열려 있는 팝업의 SceneRenderer (update 전파용)
    this._popupDetach = [];        // 팝업 renderer 의 매니저 detach 콜백들
    this._navigating = false;      // 전환 중 재진입(연타) 차단
  }

  // ── 게임 접점 훅 ──────────────────────────────────────────

  /** 흐름도 조건 분기 키의 술어 등록 (start() 전에). 반환값 truthy=분기 채택. async 허용. */
  defineCondition(key, fn) {
    if (typeof fn !== 'function') throw new Error('[FlowDriver] defineCondition: 함수가 필요합니다 — ' + key);
    this._conditions[key] = fn;
    return this;
  }

  /** 드라이버 이벤트 구독. 'scene:enter' → { sceneUuid, sceneName, renderer, popup, tabId }. 반환=구독해제. */
  on(eventName, handler) {
    (this._handlers[eventName] = this._handlers[eventName] || new Set()).add(handler);
    return () => this._handlers[eventName]?.delete(handler);
  }

  _emit(eventName, payload) { this._handlers[eventName]?.forEach(h => { try { h(payload); } catch (e) { console.error('[FlowDriver] ' + eventName + ' 핸들러 오류:', e); } }); }

  /** 현재 표시 중인 씬 — { uuid, name, renderer } | null. nav 진입 중엔 nav 호스트 기준. */
  get current() { return this._current; }

  // ── 시작 ─────────────────────────────────────────────────

  /** scenes-index.json + scene-flow.json 로드 → 시작 씬(entrySceneUuid) 표시. */
  async start() {
    const [idxRes, flowRes] = await Promise.all([
      fetch(this._base + 'scenes-index.json', { cache: 'no-store' }),
      fetch(this._base + 'scene-flow.json', { cache: 'no-store' }),
    ]);
    if (!idxRes.ok) throw new Error('[FlowDriver] scenes-index.json 로드 실패(HTTP ' + idxRes.status + ') — dataPath 확인: ' + this._base);
    if (!flowRes.ok) throw new Error('[FlowDriver] scene-flow.json 로드 실패(HTTP ' + flowRes.status + ') — dataPath 확인: ' + this._base);
    this._index = await idxRes.json();
    this._flow = await flowRes.json();
    if (!Array.isArray(this._flow.edges)) this._flow.edges = [];
    if (!this._flow.entrySceneUuid) {
      throw new Error('[FlowDriver] 시작 씬이 지정되지 않았습니다 — ui-editor "UI 흐름도"에서 씬 노드를 우클릭해 "시작 씬으로 지정" 후 다시 publish 하세요.');
    }
    this._auditHooks();
    await this._transitionTo(this._resolveOrThrow({ uuid: this._flow.entrySceneUuid, name: this._flow.entrySceneName }), null, { pushHistory: false });
    return this;
  }

  // ── 게임 사건 → 흐름 발화 ─────────────────────────────────

  /**
   * 문서 엣지(트리거 없는 연결) 발화. ref = 엣지 label("게임오버 시") 또는 도착 씬 이름/uuid.
   * label 우선, 현재 씬 출발 엣지 우선. 매칭 엣지가 없는 씬 이름/uuid 는 goto() 로 처리된다.
   */
  async fire(ref) {
    const docEdges = this._flow.edges.filter(e => !e.trigger);
    const fromCur = e => this._current && e.fromSceneUuid === this._current.uuid;
    let edge = docEdges.find(e => e.label === ref && fromCur(e)) || docEdges.find(e => e.label === ref);
    if (!edge) {
      const target = this._resolve(typeof ref === 'string' ? { uuid: ref, name: ref } : ref);
      if (!target) throw new Error('[FlowDriver] fire("' + ref + '") — 일치하는 문서 엣지 label 도, 씬도 없습니다. scene-flow.json 의 label/씬 이름과 대조하세요.');
      return this.goto(target);
    }
    return this._followEdge(edge);
  }

  /** 특정 씬으로 이동. ref = 씬 이름/uuid 또는 { uuid?, name? }. 현재 씬→대상 문서 엣지가 있으면 그 전환효과를 쓴다. */
  async goto(ref) {
    const target = this._resolveOrThrow(typeof ref === 'string' ? { uuid: ref, name: ref } : ref);
    const edge = this._flow.edges.find(e => !e.trigger && e.toSceneUuid === target.uuid
      && this._current && e.fromSceneUuid === this._current.uuid) || null;
    if (edge) return this._followEdge(edge);
    if (this._isPopup(target)) return this._openPopup(target, null);
    return this._transitionTo(target, null);
  }

  /** 열린 팝업 닫기(씬 이동 없음). trigger 없는 __close__ 문서 엣지("아무곳 터치 시 닫기" 등)를 게임 사건 시점에 실행하는 공개 경로 — 매니저 detach 까지 정리한다. */
  async closePopup() { return this._closePopupIfOpen(); }

  /** 이전 씬으로(이력 pop). 팝업이 열려 있으면 먼저 닫는다. __back__ 센티널과 동일 동작. */
  async back(opts = {}) {
    await this._closePopupIfOpen();
    const prev = this._history.pop();
    if (!prev) { console.warn('[FlowDriver] back() — 씬 이력이 비어 있습니다. 무시.'); return; }
    return this._transitionTo(this._resolveOrThrow({ uuid: prev }), opts.edge || null, { pushHistory: false });
  }

  /** 커스텀 바인딩 데이터 전파 — 살아있는 renderer 전원 + 이후 생성분(show 전 시드용 버퍼). */
  update(data) {
    this._merge(this._dataBuffer, data);
    for (const r of this._renderers.values()) r.update(data);
    if (this._popupRenderer) this._popupRenderer.update(data);
    return this;
  }

  // ── 씬 해석 (uuid 우선 · 이름 fallback — SKILL.md §2 규약) ──

  _resolve(ref) {
    if (!ref) return null;
    const scenes = (this._index && this._index.scenes) || [];
    return scenes.find(s => ref.uuid && s.uuid === ref.uuid)
        || scenes.find(s => ref.name && s.name === ref.name) || null;
  }

  _resolveOrThrow(ref) {
    const hit = this._resolve(ref);
    if (!hit) throw new Error('[FlowDriver] 씬 해석 실패 — ' + JSON.stringify(ref) + ' 이(가) scenes-index.json 에 없습니다(미publish 또는 이름 변경).');
    return hit;
  }

  _isPopup(entry) { return entry.sceneType === 'popup' || (entry.name || '').indexOf('pop_') === 0; }

  async _fetchContract(entry) {
    const url = this._base + entry.contract;
    const res = await fetch(url);
    if (!res.ok) throw new Error('[FlowDriver] contract 로드 실패(HTTP ' + res.status + '): ' + url);
    return res.json();
  }

  // ── 엣지 실행 ─────────────────────────────────────────────

  /** 버튼 이벤트 1건 → 같은 (출발씬, eventName) 의 조건 엣지들을 위에서부터 평가해 1개 채택. */
  async _onTrigger(fromUuid, eventName) {
    if (this._navigating) return; // 전환 중 연타 차단
    const candidates = this._flow.edges.filter(e =>
      e.fromSceneUuid === fromUuid && e.trigger && e.trigger.eventName === eventName);
    let fallback = null;
    for (const e of candidates) {
      const cond = e.trigger.condition;
      if (!cond || cond === 'else') { if (!fallback) fallback = e; continue; }
      const fn = this._conditions[cond];
      if (!fn) {
        console.error('[FlowDriver] 조건 키 미등록: \'' + cond + '\' — flow.defineCondition(\'' + cond + '\', () => ...) 를 start() 전에 등록하세요. 이 분기는 건너뜁니다.');
        continue;
      }
      if (await fn()) return this._followEdge(e);
    }
    if (fallback) return this._followEdge(fallback);
    console.warn('[FlowDriver] "' + eventName + '" — 채택된 분기가 없습니다(모든 조건 false, else 없음). 이동하지 않습니다.');
  }

  async _followEdge(edge) {
    if (edge.toSceneUuid === CLOSE) return this._closePopupIfOpen();
    if (edge.toSceneUuid === BACK) return this.back({ edge });
    const target = this._resolveOrThrow({ uuid: edge.toSceneUuid, name: edge.toSceneName });
    if (this._isPopup(target)) return this._openPopup(target, edge);
    return this._transitionTo(target, edge);
  }

  // ── 씬 전환 (SKILL.md §6 표준 절차의 기계화) ──────────────

  async _transitionTo(target, edge, { pushHistory = true } = {}) {
    if (this._navigating) return;
    this._navigating = true;
    try {
      await this._closePopupIfOpen(); // 팝업을 띄운 채 뒤 화면만 바뀌지 않게 — 항상 닫고 전환
      const from = this._current;

      // nav 호스팅 도착 — 도착 contract 직접 load 금지, navContract 진입 + switchTab (§2 hostedBy 규칙)
      const hosted = (edge && edge.toHostedBy && edge.toHostedBy[0]) || null;
      const hostEntry = hosted ? this._resolve({ uuid: hosted.navSceneUuid, name: hosted.navScene }) : null;
      if (hostEntry) {
        if (from && from.uuid === hostEntry.uuid) {
          // 같은 nav 안의 탭 이동 — 화면 전환 없이 탭만 스위치 (scene:enter 는 nav:tabchange 가 통지)
          from.renderer.switchTab(hosted.tabId);
          this._navigating = false;
          return;
        }
        const navR = await this._getRenderer(hostEntry);
        await this._swap(from, navR, hostEntry, edge, pushHistory);
        navR.switchTab(hosted.tabId);
        return;
      }

      const toR = await this._getRenderer(target);
      await this._swap(from, toR, target, edge, pushHistory);
    } finally {
      this._navigating = false;
    }
  }

  /** 전환 시퀀스 공통부 — Out 재생 → hide → show → In 재생 → 이력/현재/통지 갱신. */
  async _swap(from, toR, target, edge, pushHistory) {
    if (from && from.renderer !== toR) {
      await from.renderer.playTransition((edge && edge.transitionOut) || null);
      from.renderer.hide();
    }
    toR.show();
    toR.playTransition((edge && edge.transitionIn) || null);
    if (pushHistory && from && from.uuid !== target.uuid) this._history.push(from.uuid);
    this._current = { uuid: target.uuid, name: target.name, renderer: toR };
    this._emit('scene:enter', { sceneUuid: target.uuid, sceneName: target.name, renderer: toR, popup: false });
  }

  /** renderer 캐시 — 최초 1회 load + 엣지 배선 + 매니저 attach + 버퍼 시드. 구독은 인스턴스에 유지된다. */
  async _getRenderer(entry) {
    let r = this._renderers.get(entry.uuid);
    if (r) return r;
    const contract = await this._fetchContract(entry);
    // nav 탭 씬 이름 해석기 주입 — scenes-index 기준 (renderer 자체 폴백보다 명시 주입 권장 규약)
    r = new SceneRenderer(this._mount, {
      ...this._rendererOpts,
      sceneFetch: async (name) => this._fetchContract(this._resolveOrThrow({ name })),
    });
    r.loadSync(contract);
    this._renderers.set(entry.uuid, r);
    this._wireRenderer(r, entry.uuid);
    // nav 호스트 — 탭 마운트마다 새 sub-renderer 가 생기므로 매번 재배선 + 재attach (§3 함정 체크리스트)
    if (contract.sceneType === 'navigation') {
      r.on('nav:tabchange', ({ tabId, sceneName, renderer }) => {
        if (!renderer) return;
        const sub = this._resolve({ uuid: renderer.sceneUuid, name: sceneName });
        if (sub) this._wireRenderer(renderer, sub.uuid);
        else this._attachManagers(renderer); // 해석 실패해도 표준 바인딩은 살린다
        this._emit('scene:enter', {
          sceneUuid: sub ? sub.uuid : renderer.sceneUuid, sceneName: sceneName,
          renderer, popup: false, tabId,
        });
      });
    }
    return r;
  }

  /** renderer 1개에 엣지 구독 + 매니저 attach + 데이터 버퍼 시드 (인스턴스당 1회). */
  _wireRenderer(renderer, sceneUuid) {
    if (this._wired.has(renderer)) return;
    this._wired.add(renderer);
    const eventNames = new Set(this._flow.edges
      .filter(e => e.fromSceneUuid === sceneUuid && e.trigger && e.trigger.eventName)
      .map(e => e.trigger.eventName));
    for (const name of eventNames) {
      renderer.on(name, () => { this._onTrigger(sceneUuid, name).catch(err => console.error('[FlowDriver] 엣지 실행 오류:', err)); });
    }
    this._attachManagers(renderer);
    if (Object.keys(this._dataBuffer).length) renderer.update(this._dataBuffer);
  }

  _attachManagers(renderer) {
    const out = [];
    for (const key of ['economy', 'progress']) {
      const m = this._managers[key];
      if (m && typeof m.attachRenderer === 'function') out.push(m.attachRenderer(renderer));
    }
    return out;
  }

  // ── 팝업 (pop_* / __close__ — PopupManager 규약) ───────────

  async _openPopup(target, edge) {
    await this._closePopupIfOpen(); // 동시에 1개 — 팝업→팝업은 닫고 열기
    if (this._current && edge && edge.transitionOut) {
      console.info('[FlowDriver] 팝업 엣지의 transitionOut 은 재생하지 않습니다(출발 씬이 화면에 남는 오버레이 규약) — ' + (edge.fromSceneName || '') + '→' + target.name);
    }
    const on = {};
    for (const e of this._flow.edges) {
      if (e.fromSceneUuid !== target.uuid || !e.trigger || !e.trigger.eventName) continue;
      if (!on[e.trigger.eventName]) {
        const evName = e.trigger.eventName;
        on[evName] = () => { this._onTrigger(target.uuid, evName).catch(err => console.error('[FlowDriver] 팝업 엣지 실행 오류:', err)); };
      }
    }
    await this._popups.open(this._base + target.contract, {
      data: Object.keys(this._dataBuffer).length ? this._dataBuffer : null,
      on,
      after: (r) => {
        this._popupRenderer = r;
        this._popupDetach = this._attachManagers(r);
      },
    });
    this._popupUuid = target.uuid;
    this._emit('scene:enter', { sceneUuid: target.uuid, sceneName: target.name, renderer: this._popupRenderer, popup: true });
  }

  async _closePopupIfOpen() {
    if (!this._popups.isOpen) return;
    await this._popups.close();
    this._popupDetach.forEach(off => { try { off(); } catch (e) {} });
    this._popupDetach = [];
    this._popupRenderer = null;
    this._popupUuid = null;
  }

  // ── 자가진단 — "자동이 안 되는 부분"의 목록화 (훅 되먹임) ──

  _auditHooks() {
    const condKeys = new Set();
    this._flow.edges.forEach(e => {
      const c = e.trigger && e.trigger.condition;
      if (c && c !== 'else') condKeys.add(c);
    });
    const unregistered = [...condKeys].filter(k => !this._conditions[k]);
    const docEdges = this._flow.edges.filter(e => !e.trigger).map(e => ({
      label: e.label || '', from: e.fromSceneName || e.fromSceneUuid, to: e.toSceneName || e.toSceneUuid,
    }));
    if (typeof window !== 'undefined') {
      const audit = window.__uiWiringAudit = window.__uiWiringAudit || { scenes: {} };
      audit.flow = { unregisteredConditions: unregistered, documentEdges: docEdges };
    }
    if (unregistered.length) {
      console.warn('[FlowDriver] 미등록 조건 키 ' + unregistered.length + '건 — flow.defineCondition() 으로 술어를 등록하세요(미등록 분기는 건너뜁니다).');
      unregistered.forEach(k => console.warn('  - \'' + k + '\''));
    }
    if (docEdges.length) {
      console.info('[FlowDriver] 문서 엣지(게임이 fire() 로 발화) ' + docEdges.length + '건:');
      docEdges.forEach(d => console.info('  - ' + (d.label ? '"' + d.label + '" ' : '(label 없음) ') + d.from + '→' + d.to));
    }
  }

  /** 두 번째 인자 객체를 첫 번째에 깊은 병합(중첩 plain object 만) — update() 버퍼 누적용. */
  _merge(dst, src) {
    for (const [k, v] of Object.entries(src || {})) {
      if (v && typeof v === 'object' && !Array.isArray(v) && dst[k] && typeof dst[k] === 'object' && !Array.isArray(dst[k])) this._merge(dst[k], v);
      else dst[k] = v;
    }
    return dst;
  }
}

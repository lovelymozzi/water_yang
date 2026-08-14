// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 프로그레스 매니저 — 스테이지 진행도(현재 스테이지·클리어 기록·별점·최고 점수)를 한 곳에서 관리한다.
// 규칙:
//   - 진행도는 호스트(아웃게임) 전유 — 인게임 카트리지는 이 파일을 import 하지 않는다 (GameSession 프로토콜: 카트리지는 end 보고만).
//   - 해금은 선형: 스테이지 N 클리어 → N+1 해금. (맵형·분기형 해금이 필요하면 사용자와 스펙 협의 후 확장.)
//   - 상태는 localStorage 에 단일 JSON({current, records})으로 영속화. 저장 키 = `${storagePrefix}progress_v1`.
//   - 게임 특화 수치(시작 스테이지·최대 스테이지)는 전부 생성자 옵션 — 이 파일에 상수를 심지 말 것.
//   - 씬 표시는 표준 bindingKey — `stage.current` / `stage.next+1`~`stage.next+3` (attachRenderer 참조).
//     `stage.next+N` = 맵 고정 위치에 다음 스테이지 번호 표시(current+N). maxStage 초과분은 빈 문자열.
//     레이아웃 종속 키(stage.n1 처럼 버튼 배치에 묶인 것)는 표준이 아니다 — getStars()/isUnlocked() 값을 게임 코드가 매핑한다.
//   - 하트·코인은 EconomyManager 전담 — 여기 넣지 않는다.
//   - recordClear 는 async — Authority 승인을 거친다(계약 정본 = game-session.js 상단 주석).
//     기본 LOCAL_AUTHORITY(즉시 승인), 경쟁 표면 게임은 `authority` 주입 + GameSession 티켓 동봉.
//     읽기(getCurrentStage 등)는 캐시 기준 동기 — localStorage 는 표시용 캐시이며 진실이 아니다.

import { LOCAL_AUTHORITY } from './game-session.js';

const STORAGE_KEY_SUFFIX = 'progress_v1';

export class ProgressManager {
  /**
   * @param {object} [opts]
   * @param {string} [opts.storagePrefix] - localStorage 키 프리픽스 (게임 프리픽스, 예: 'cc_')
   * @param {number} [opts.initialStage=1] - 최초 실행 시 해금돼 있는 스테이지
   * @param {number|null} [opts.maxStage=null] - 마지막 스테이지 번호 (null = 제한 없음)
   * @param {object} [opts.authority] - Authority 계약 구현체 (기본 LOCAL_AUTHORITY — game-session.js 계약 주석 참조)
   */
  constructor({ storagePrefix = '', initialStage = 1, maxStage = null, authority = null } = {}) {
    this._authority = authority || LOCAL_AUTHORITY;
    this._key = storagePrefix + STORAGE_KEY_SUFFIX;
    this._initialStage = Math.max(1, Math.floor(initialStage));
    this._maxStage = maxStage == null ? null : Math.max(1, Math.floor(maxStage));
    this._renderers = new Set();      // attachRenderer 된 SceneRenderer 들
    this._state = this._load();       // { current, records: { [stage]: { stars, bestScore, clears } } }
  }

  get maxStage() { return this._maxStage; }

  // ── 진행도 ────────────────────────────────────────────

  /** 현재 도전 가능한 최신 스테이지(= 해금된 가장 높은 스테이지). */
  getCurrentStage() { return this._state.current; }

  /** 해당 스테이지가 해금됐는지. */
  isUnlocked(stage) {
    const n = Math.floor(stage);
    return n >= 1 && n <= this._state.current;
  }

  /**
   * 스테이지 클리어 기록. 별점·점수는 기존 기록보다 좋을 때만 갱신(최고 기록 유지).
   * 현재 최신 스테이지를 클리어하면 다음 스테이지를 해금한다(maxStage 초과 없음).
   * 권위 승인을 거친다 — 거부(티켓 불일치·불가능 점수 등 서버 판정) 시 기록 없이 throw.
   * @param {number} stage
   * @param {object} [result] - { stars?, score?, ticket? } — ticket = GameSession onEnd 가 동봉한 세션 티켓
   * @returns {Promise<{ current:number, stars:number, bestScore:number, clears:number }>} 갱신된 기록
   */
  async recordClear(stage, { stars = 0, score = 0, ticket = null } = {}) {
    const n = Math.floor(stage);
    if (!this.isUnlocked(n)) {
      throw new Error(`[ProgressManager] recordClear(${n}) — 해금되지 않은 스테이지 (current: ${this._state.current})`);
    }
    const safeStars = Math.max(0, Math.floor(stars));
    const safeScore = Math.max(0, Math.floor(score));
    const res = await this._authority.approve({ op: 'commitProgress', stage: n, stars: safeStars, score: safeScore, ticket });
    if (!res || res.ok !== true) {
      throw new Error(`[ProgressManager] recordClear(${n}) — 권위(authority)가 커밋을 거부함`);
    }
    const rec = this._state.records[n] || (this._state.records[n] = { stars: 0, bestScore: 0, clears: 0 });
    rec.clears += 1;
    rec.stars = Math.max(rec.stars, safeStars);
    rec.bestScore = Math.max(rec.bestScore, safeScore);
    if (n === this._state.current && (this._maxStage == null || this._state.current < this._maxStage)) {
      this._state.current += 1;
    }
    if (Number.isFinite(res.current)) { // 권위가 준 해금 지점이 진실 — 로컬 계산을 덮어쓴다
      this._state.current = Math.max(this._initialStage, Math.floor(res.current));
      if (this._maxStage != null) this._state.current = Math.min(this._state.current, this._maxStage);
    }
    this._save();
    this._pushBindings();
    return { current: this._state.current, stars: rec.stars, bestScore: rec.bestScore, clears: rec.clears };
  }

  /** 해당 스테이지의 최고 별점 (기록 없으면 0). */
  getStars(stage) { return this._state.records[Math.floor(stage)]?.stars || 0; }

  /** 해당 스테이지의 최고 점수 (기록 없으면 0). */
  getBestScore(stage) { return this._state.records[Math.floor(stage)]?.bestScore || 0; }

  /** 해당 스테이지의 클리어 횟수 (기록 없으면 0). */
  getClears(stage) { return this._state.records[Math.floor(stage)]?.clears || 0; }

  // ── 씬 연동 ───────────────────────────────────────────

  /** 표준 bindingKey 페이로드 — 씬 텍스트 bindingKey 를 stage.current / stage.next+1~+3 으로 설정할 것. */
  getBindingData() {
    const cur = this._state.current;
    const stage = { current: String(cur) };
    for (let n = 1; n <= 3; n++) {
      const next = cur + n;
      stage[`next+${n}`] = (this._maxStage != null && next > this._maxStage) ? '' : String(next);
    }
    return { stage };
  }

  /**
   * SceneRenderer 에 진행도 바인딩을 연결한다. 값은 recordClear 시점에만 바뀌므로 타이머 없이 변경 시 push.
   * nav 탭 전환으로 sub-renderer 가 교체되면 새 renderer 로 다시 attach 한다(구 renderer 는 detach).
   * @returns {Function} detach — 해당 renderer 연결 해제
   */
  attachRenderer(renderer) {
    if (!renderer || typeof renderer.update !== 'function') {
      throw new Error('ProgressManager.attachRenderer: SceneRenderer 인스턴스가 필요합니다');
    }
    this._renderers.add(renderer);
    renderer.update(this.getBindingData());
    return () => { this._renderers.delete(renderer); };
  }

  // ── 내부 ──────────────────────────────────────────────

  _pushBindings() {
    if (this._renderers.size === 0) return;
    const data = this.getBindingData();
    for (const r of this._renderers) r.update(data);
  }

  _load() {
    const fallback = { current: this._initialStage, records: {} };
    const raw = localStorage.getItem(this._key);
    if (raw == null) return fallback;
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      console.warn('[ProgressManager] 저장 데이터 파싱 실패 — 초기값으로 시작:', this._key, e);
      return fallback;
    }
    const state = {
      current: Number.isFinite(parsed?.current) ? Math.max(this._initialStage, Math.floor(parsed.current)) : this._initialStage,
      records: {},
    };
    if (this._maxStage != null) state.current = Math.min(state.current, this._maxStage);
    const rawRecords = (parsed && typeof parsed.records === 'object' && parsed.records) || {};
    for (const [k, v] of Object.entries(rawRecords)) {
      const n = Math.floor(Number(k));
      if (!Number.isFinite(n) || n < 1) continue;
      state.records[n] = {
        stars: Number.isFinite(v?.stars) ? Math.max(0, Math.floor(v.stars)) : 0,
        bestScore: Number.isFinite(v?.bestScore) ? Math.max(0, Math.floor(v.bestScore)) : 0,
        clears: Number.isFinite(v?.clears) ? Math.max(0, Math.floor(v.clears)) : 0,
      };
    }
    return state;
  }

  _save() {
    localStorage.setItem(this._key, JSON.stringify(this._state));
  }
}

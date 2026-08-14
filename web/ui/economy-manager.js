// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 이코노미 매니저 — 하트(플레이 횟수)·코인(재화)을 한 곳에서 관리한다.
// 규칙:
//   - 하트/재화는 호스트(아웃게임) 전유 — 인게임 카트리지는 이 파일을 import 하지 않는다 (GameSession 프로토콜).
//   - 하트 재생은 anchor 방식: heartAnchorMs 기준 경과 시간으로 오프라인 경과분까지 일괄 지급.
//   - 상태는 localStorage 에 단일 JSON({hearts, heartAnchorMs, coins})으로 영속화.
//     키 충돌 방지를 위해 게임별 storagePrefix('cc_' 등)를 넣는다. 저장 키 = `${storagePrefix}economy_v1`.
//   - 게임 특화 수치(최대 하트·재생 간격·보상액)는 전부 생성자 옵션 — 이 파일에 상수를 심지 말 것.
//   - 씬 표시는 표준 bindingKey — `heart.current` / `heart.timer` / `coin.current` (attachRenderer 참조).
//   - 변이(소비·지급·지불)는 전부 async — Authority 승인을 거친다(계약 정본 = game-session.js 상단 주석).
//     기본 LOCAL_AUTHORITY(즉시 승인), 경쟁 표면 게임은 서버 구현체를 `authority` 옵션으로 주입.
//     읽기(getHearts 등)는 캐시 기준 동기 — localStorage 는 표시용 캐시이며 진실이 아니다.

import { LOCAL_AUTHORITY } from './game-session.js';

const STORAGE_KEY_SUFFIX = 'economy_v1';

export class EconomyManager {
  /**
   * @param {object} [opts]
   * @param {string} [opts.storagePrefix] - localStorage 키 프리픽스 (게임 프리픽스, 예: 'cc_')
   * @param {number} [opts.maxHearts=5] - 최대 하트 수
   * @param {number} [opts.heartRegenMs=1800000] - 하트 1개 재생 간격(ms, 기본 30분)
   * @param {number} [opts.initialCoins=0] - 최초 실행 시 지급 코인
   * @param {string} [opts.legacyKey] - 구 저장 키(있으면 새 키 부재 시 1회 마이그레이션, 예: 'cc_runtime_progress_v1')
   * @param {object} [opts.authority] - Authority 계약 구현체 (기본 LOCAL_AUTHORITY — game-session.js 계약 주석 참조)
   */
  constructor({ storagePrefix = '', maxHearts = 5, heartRegenMs = 30 * 60 * 1000, initialCoins = 0, legacyKey = null, authority = null } = {}) {
    this._authority = authority || LOCAL_AUTHORITY;
    this._key = storagePrefix + STORAGE_KEY_SUFFIX;
    this._maxHearts = Math.max(1, Math.floor(maxHearts));
    this._regenMs = Math.max(1000, Math.floor(heartRegenMs));
    this._initialCoins = Math.max(0, Math.floor(initialCoins));
    this._renderers = new Set();      // attachRenderer 된 SceneRenderer 들
    this._tickId = null;              // 1초 바인딩 갱신 타이머
    this._state = this._load(legacyKey);
    if (this._applyRegen()) this._save();
  }

  get maxHearts() { return this._maxHearts; }

  // ── 하트 ──────────────────────────────────────────────

  getHearts() {
    this._regenAndPersist();
    return this._state.hearts;
  }

  /**
   * 하트 1개 소비(게임 시작 등). 재생 적용·권위 승인 후 부족/거부면 false — 호스트가 refill 팝업을 연다.
   * 만땅에서 소비할 때만 anchor 를 지금으로 리셋한다(재생 중이던 카운트다운은 보존).
   * @returns {Promise<boolean>} — `await economy.consumeHeart()` 로 판정할 것(미대기 시 Promise 는 항상 truthy)
   */
  async consumeHeart(now = Date.now()) {
    this._applyRegen(now);
    if (this._state.hearts <= 0) { this._save(); return false; } // 캐시 기준 선차단 — 서버 왕복 없이 refill 유도
    const res = await this._authority.approve({ op: 'consumeHeart', now });
    const adopted = this._adoptAuthority(res);
    if (!res || res.ok !== true) { this._commit(); return false; }
    if (!adopted.hearts) { // 권위가 잔액을 안 줬으면 로컬 규칙 적용 (LOCAL_AUTHORITY 경로)
      const wasFull = this._state.hearts >= this._maxHearts;
      this._state.hearts -= 1;
      if (wasFull) this._state.heartAnchorMs = now;
    }
    this._commit();
    return true;
  }

  /** 하트 지급(클리어 보상·refill 구매·광고 보상). 최대치 초과분은 버린다. 거부 시 값 미변경. */
  async grantHearts(n, now = Date.now(), reason = '') {
    this._applyRegen(now);
    const amount = Math.max(0, Math.floor(n));
    const res = await this._authority.approve({ op: 'grantHearts', n: amount, now, reason });
    const adopted = this._adoptAuthority(res);
    if (res && res.ok === true && !adopted.hearts) {
      this._state.hearts = Math.min(this._maxHearts, this._state.hearts + amount);
      if (this._state.hearts >= this._maxHearts) this._state.heartAnchorMs = now;
    }
    this._commit();
    return this._state.hearts;
  }

  /** 하트를 최대치로 채운다(refill 상품). */
  refillHearts(now = Date.now(), reason = 'refill') { return this.grantHearts(this._maxHearts, now, reason); }

  /** 다음 하트까지 남은 시간 문자열 — "M:SS", 만땅이면 "Max". */
  getHeartTimer(now = Date.now()) {
    this._regenAndPersist(now);
    if (this._state.hearts >= this._maxHearts) return 'Max';
    const elapsed = Math.max(0, now - this._state.heartAnchorMs);
    const remain = Math.max(0, this._regenMs - (elapsed % this._regenMs));
    const totalSec = Math.ceil(remain / 1000);
    const min = Math.floor(totalSec / 60);
    const sec = totalSec % 60;
    return `${min}:${String(sec).padStart(2, '0')}`;
  }

  // ── 코인 ──────────────────────────────────────────────

  getCoins() { return this._state.coins; }

  /** 코인 지급(클리어 보상·상점 구매 등). 거부 시 값 미변경. */
  async grantCoins(n, reason = '') {
    const amount = Math.max(0, Math.floor(n));
    const res = await this._authority.approve({ op: 'grantCoins', n: amount, reason });
    const adopted = this._adoptAuthority(res);
    if (res && res.ok === true && !adopted.coins) this._state.coins += amount;
    this._commit();
    return this._state.coins;
  }

  /**
   * 코인 지불 시도. 잔액 부족·권위 거부면 차감 없이 false — 호스트가 상점 유도 등을 한다.
   * @returns {Promise<boolean>} — `await economy.spendCoins(n)` 로 판정할 것(미대기 시 Promise 는 항상 truthy)
   */
  async spendCoins(n, reason = '') {
    const cost = Math.max(0, Math.floor(n));
    if (this._state.coins < cost) return false; // 캐시 기준 선차단 — 서버 왕복 없이 상점 유도
    const res = await this._authority.approve({ op: 'spendCoins', n: cost, reason });
    const adopted = this._adoptAuthority(res);
    if (!res || res.ok !== true) { this._commit(); return false; }
    if (!adopted.coins) this._state.coins -= cost;
    this._commit();
    return true;
  }

  // ── 씬 연동 ───────────────────────────────────────────

  /** 표준 bindingKey 페이로드 — 씬 텍스트 bindingKey 를 heart.current / heart.timer / coin.current 로 설정할 것. */
  getBindingData(now = Date.now()) {
    return {
      heart: {
        current: String(this.getHearts()),
        timer: this.getHeartTimer(now),
      },
      coin: {
        current: String(this._state.coins),
      },
    };
  }

  /**
   * SceneRenderer 에 하트/코인 바인딩을 연결하고 1초마다 자동 갱신한다(재생 타이머 표시용).
   * nav 탭 전환으로 sub-renderer 가 교체되면 새 renderer 로 다시 attach 한다(구 renderer 는 detach).
   * @returns {Function} detach — 해당 renderer 연결 해제(마지막 하나가 빠지면 타이머도 정지)
   */
  attachRenderer(renderer) {
    if (!renderer || typeof renderer.update !== 'function') {
      throw new Error('EconomyManager.attachRenderer: SceneRenderer 인스턴스가 필요합니다');
    }
    this._renderers.add(renderer);
    renderer.update(this.getBindingData());
    if (this._tickId == null) {
      this._tickId = setInterval(() => this._pushBindings(), 1000);
    }
    return () => {
      this._renderers.delete(renderer);
      if (this._renderers.size === 0 && this._tickId != null) {
        clearInterval(this._tickId);
        this._tickId = null;
      }
    };
  }

  // ── 내부 ──────────────────────────────────────────────

  /**
   * 권위 응답의 권위값 채택 — 서버가 잔액을 주면 로컬 캐시를 그 값으로 덮어쓴다(거부 응답이어도 동기화).
   * @returns {{hearts:boolean, coins:boolean}} 필드별 채택 여부 — false 면 호출부가 로컬 규칙을 적용한다.
   */
  _adoptAuthority(res) {
    const adopted = { hearts: false, coins: false };
    if (!res) return adopted;
    if (Number.isFinite(res.hearts)) {
      this._state.hearts = Math.max(0, Math.min(this._maxHearts, Math.floor(res.hearts)));
      adopted.hearts = true;
    }
    if (Number.isFinite(res.heartAnchorMs)) this._state.heartAnchorMs = res.heartAnchorMs;
    if (Number.isFinite(res.coins)) {
      this._state.coins = Math.max(0, Math.floor(res.coins));
      adopted.coins = true;
    }
    return adopted;
  }

  /** 변이 확정 — 영속화 + 바인딩 push (모든 변이 메서드의 공통 마무리). */
  _commit() {
    this._save();
    this._pushBindings();
  }

  _pushBindings() {
    if (this._renderers.size === 0) return;
    const data = this.getBindingData();
    for (const r of this._renderers) r.update(data);
  }

  /** anchor 기준 재생 적용. 상태가 바뀌면 true. */
  _applyRegen(now = Date.now()) {
    const s = this._state;
    if (s.hearts >= this._maxHearts) {
      if (s.heartAnchorMs !== now) { s.heartAnchorMs = now; return true; }
      return false;
    }
    const elapsed = now - s.heartAnchorMs;
    if (elapsed < this._regenMs) return false;
    const gained = Math.floor(elapsed / this._regenMs);
    s.hearts = Math.min(this._maxHearts, s.hearts + gained);
    s.heartAnchorMs += gained * this._regenMs;
    if (s.hearts >= this._maxHearts) s.heartAnchorMs = now;
    return true;
  }

  _regenAndPersist(now = Date.now()) {
    if (this._applyRegen(now)) this._save();
  }

  _load(legacyKey) {
    const now = Date.now();
    const fallback = { hearts: this._maxHearts, heartAnchorMs: now, coins: this._initialCoins };
    let raw = localStorage.getItem(this._key);
    let fromLegacy = false;
    if (raw == null && legacyKey) {
      raw = localStorage.getItem(legacyKey);
      fromLegacy = raw != null;
    }
    if (raw == null) return fallback;
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      console.warn('[EconomyManager] 저장 데이터 파싱 실패 — 초기값으로 시작:', this._key, e);
      return fallback;
    }
    const state = {
      hearts: Number.isFinite(parsed?.hearts) ? Math.max(0, Math.min(this._maxHearts, Math.floor(parsed.hearts))) : this._maxHearts,
      heartAnchorMs: Number.isFinite(parsed?.heartAnchorMs) ? parsed.heartAnchorMs : now,
      coins: Number.isFinite(parsed?.coins) ? Math.max(0, Math.floor(parsed.coins)) : this._initialCoins,
    };
    if (fromLegacy) {
      console.log('[EconomyManager] 구 저장 키에서 마이그레이션:', legacyKey, '→', this._key);
      localStorage.setItem(this._key, JSON.stringify(state));
    }
    return state;
  }

  _save() {
    localStorage.setItem(this._key, JSON.stringify(this._state));
  }
}

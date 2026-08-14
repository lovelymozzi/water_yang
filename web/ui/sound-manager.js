// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 사운드 매니저 — BGM/SFX 재생을 한 곳에서 관리한다.
// 규칙:
//   - 브라우저는 사용자 제스처 전 오디오 재생을 막으므로, BGM 은 unlockOnFirstGesture() 로 첫 제스처에서 시작한다.
//     (제스처 전 playBgm() 호출은 pending 으로 보관했다가 첫 제스처에서 자동 재생)
//   - 볼륨은 master → bgm/sfx 2단 채널. 실효 볼륨 = master × 채널.
//   - 뮤트·볼륨은 localStorage 에 영속화. 키 충돌 방지를 위해 게임별 storagePrefix('cc_' 등)를 넣는다.

const CHANNELS = ['master', 'bgm', 'sfx'];

export class SoundManager {
  /**
   * @param {object} [opts]
   * @param {string} [opts.storagePrefix] - localStorage 키 프리픽스 (게임 프리픽스, 예: 'cc_')
   */
  constructor({ storagePrefix = '' } = {}) {
    this._prefix = storagePrefix;
    this._unlocked = false;
    this._pendingBgm = null;          // 제스처 전 playBgm 요청 { src, loop }
    this._pendingUnlockCbs = null;    // unlock 대기 콜백들 — 리스너는 1벌만 걸고 콜백은 여기에 합류
    this._bgm = null;                 // 현재 BGM Audio 엘리먼트
    this._bgmSrc = null;
    this._sfxCache = new Map();       // src → Audio (재생 시 cloneNode 로 중첩 허용)
    this._muted = this._loadBool('snd_muted', false);
    this._vol = {
      master: this._loadNum('snd_vol_master', 1),
      bgm: this._loadNum('snd_vol_bgm', 1),
      sfx: this._loadNum('snd_vol_sfx', 1),
    };
  }

  get muted() { return this._muted; }

  /**
   * 첫 사용자 제스처(pointerdown/keydown)에서 오디오를 unlock 하고 pending BGM 을 재생한다.
   * @param {Function} [onFirst] - 첫 제스처에서 함께 실행할 콜백 (예: 로비 진입)
   */
  unlockOnFirstGesture(onFirst = null) {
    if (this._unlocked) { if (onFirst) onFirst(); return; }
    if (this._pendingUnlockCbs) { // 이미 대기 중 — 리스너를 또 걸지 않고 콜백만 합류(중복 등록 시 두 번째 콜백 유실 방지)
      if (onFirst) this._pendingUnlockCbs.push(onFirst);
      return;
    }
    this._pendingUnlockCbs = onFirst ? [onFirst] : [];
    const fire = () => {
      window.removeEventListener('pointerdown', fire);
      window.removeEventListener('keydown', fire);
      if (this._unlocked) return; // pointerdown+keydown 중복 방지
      this._unlocked = true;
      if (this._pendingBgm) {
        const { src, loop } = this._pendingBgm;
        this._pendingBgm = null;
        this.playBgm(src, { loop });
      }
      const cbs = this._pendingUnlockCbs || [];
      this._pendingUnlockCbs = null;
      cbs.forEach((cb) => cb());
    };
    window.addEventListener('pointerdown', fire);
    window.addEventListener('keydown', fire);
  }

  /**
   * BGM 재생. 제스처 전이면 pending 보관(첫 제스처에서 자동 시작), 같은 src 재호출은 무시(이어 재생).
   * @param {string} src
   * @param {object} [opts]
   * @param {boolean} [opts.loop=true]
   */
  playBgm(src, { loop = true } = {}) {
    if (!this._unlocked) { this._pendingBgm = { src, loop }; return; }
    if (this._bgm && this._bgmSrc === src && !this._bgm.paused) return;
    this.stopBgm();
    const a = new Audio(src);
    a.loop = loop;
    a.volume = this._effective('bgm');
    a.muted = this._muted;
    this._bgm = a;
    this._bgmSrc = src;
    a.play().catch((e) => console.warn('[SoundManager] BGM 재생 실패:', src, e));
  }

  stopBgm() {
    if (!this._bgm) return;
    this._bgm.pause();
    this._bgm.src = '';
    this._bgm = null;
    this._bgmSrc = null;
  }

  /** SFX 재생 — 같은 소리의 연타/중첩을 허용한다(cloneNode). 제스처 전 호출은 무음으로 무시. */
  playSfx(src) {
    if (!this._unlocked || this._muted) return;
    let base = this._sfxCache.get(src);
    if (!base) { base = new Audio(src); base.preload = 'auto'; this._sfxCache.set(src, base); }
    const a = base.cloneNode(true);
    a.volume = this._effective('sfx');
    a.play().catch((e) => console.warn('[SoundManager] SFX 재생 실패:', src, e));
  }

  setMuted(muted) {
    this._muted = !!muted;
    this._saveBool('snd_muted', this._muted);
    if (this._bgm) this._bgm.muted = this._muted;
  }

  toggleMuted() { this.setMuted(!this._muted); return this._muted; }

  /**
   * @param {'master'|'bgm'|'sfx'} channel
   * @param {number} v - 0~1
   */
  setVolume(channel, v) {
    if (!CHANNELS.includes(channel)) throw new Error(`SoundManager: 알 수 없는 채널 '${channel}' (master|bgm|sfx)`);
    this._vol[channel] = Math.min(1, Math.max(0, Number(v) || 0));
    this._saveNum('snd_vol_' + channel, this._vol[channel]);
    if (this._bgm) this._bgm.volume = this._effective('bgm');
  }

  getVolume(channel) {
    if (!CHANNELS.includes(channel)) throw new Error(`SoundManager: 알 수 없는 채널 '${channel}' (master|bgm|sfx)`);
    return this._vol[channel];
  }

  _effective(channel) { return this._vol.master * this._vol[channel]; }

  _loadBool(key, def) {
    const v = localStorage.getItem(this._prefix + key);
    return v == null ? def : v === '1';
  }
  _saveBool(key, v) { localStorage.setItem(this._prefix + key, v ? '1' : '0'); }
  _loadNum(key, def) {
    const v = parseFloat(localStorage.getItem(this._prefix + key));
    return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : def;
  }
  _saveNum(key, v) { localStorage.setItem(this._prefix + key, String(v)); }
}

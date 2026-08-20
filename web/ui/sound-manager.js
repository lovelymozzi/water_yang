// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 사운드 매니저 — BGM/SFX 재생을 한 곳에서 관리한다.
// 규칙:
//   - 브라우저는 사용자 제스처 전 오디오 재생을 막으므로, BGM 은 unlockOnFirstGesture() 로 첫 제스처에서 시작한다.
//     (제스처 전 playBgm() 호출은 pending 으로 보관했다가 첫 제스처에서 자동 재생)
//   - 볼륨은 master → bgm/sfx 2단 채널. 실효 볼륨 = master × 채널 × gain(재생별 개별 볼륨).
//     gain 은 소스마다 녹음 레벨이 다른 걸 맞추는 용도(예: 어드민의 sfxVol 0.2).
//   - 도중에 끊어야 하는 SFX(차지·루프성·글로우 등)는 playKeyedSfx(key, ...) 로 재생하고
//     stopSfx(key) 로 중단한다. 같은 key 재요청은 이전 것을 끊고 재시작한다.
//   - 뮤트·볼륨 변경은 '이미 재생 중인' SFX 에도 즉시 반영된다(시작 시점 값으로 굳지 않는다).
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
    this._sfxLive = new Set();        // 재생 중인 SFX 인스턴스 — 일괄 정지·뮤트·볼륨 반영 대상
    this._sfxKeyed = new Map();       // key → 재생 중인 Audio (키당 1개, stopSfx(key) 로 중단)
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

  /**
   * SFX 재생 — 같은 소리의 연타/중첩을 허용한다(cloneNode). 제스처 전 호출은 무음으로 무시.
   * @param {string} src
   * @param {number} [gain=1] - 이 재생만의 개별 볼륨 0~1. 실효 볼륨 = master × sfx × gain.
   */
  playSfx(src, gain = 1) {
    if (!this._unlocked || this._muted) return;
    this._spawnSfx(src, gain, null);
  }

  /**
   * 중단 가능한 SFX 재생 — key 당 1개만 살아 있다. 같은 key 로 다시 부르면 이전 것을 끊고 재시작한다.
   * (차지·글로우처럼 "켜두었다가 꺼야 하는" 소리용. 연타·중첩이 목적이면 playSfx 를 쓴다)
   * @param {string} key - 논리 슬롯 이름. src 와 별개 — 같은 슬롯에 다른 소리를 넣어도 된다.
   * @param {string} src
   * @param {number} [gain=1]
   */
  playKeyedSfx(key, src, gain = 1) {
    this.stopSfx(key);
    if (!this._unlocked || this._muted) return;
    this._sfxKeyed.set(key, this._spawnSfx(src, gain, key));
  }

  /**
   * 재생 중인 SFX 중단. BGM 은 건드리지 않는다(stopBgm 사용).
   * @param {string} [key] - playKeyedSfx 의 key. 생략하면 재생 중인 SFX 전부 중단(씬 전환 등).
   */
  stopSfx(key) {
    if (key == null) {
      this._sfxLive.forEach((a) => { a.pause(); a.currentTime = 0; });
      this._sfxLive.clear();
      this._sfxKeyed.clear();
      return;
    }
    const a = this._sfxKeyed.get(key);
    if (!a) return;
    a.pause();
    a.currentTime = 0;
    this._sfxKeyed.delete(key);
    this._sfxLive.delete(a);
  }

  setMuted(muted) {
    this._muted = !!muted;
    this._saveBool('snd_muted', this._muted);
    if (this._bgm) this._bgm.muted = this._muted;
    // 이미 재생 중인 SFX 도 즉시 반영 — playSfx 는 시작 시점에만 _muted 를 보므로 이게 없으면 계속 들린다
    this._sfxLive.forEach((a) => { a.muted = this._muted; });
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
    // 재생 중인 SFX 도 즉시 반영 — 옵션 슬라이더를 미는 동안 들리던 소리가 옛 볼륨으로 남지 않게 한다.
    // 재생별 gain 을 기억해 두었으므로 채널만 바뀌어도 각자의 상대 음량이 유지된다.
    if (channel !== 'bgm') this._sfxLive.forEach((a) => { a.volume = this._sfxVolume(a._uiGain); });
  }

  getVolume(channel) {
    if (!CHANNELS.includes(channel)) throw new Error(`SoundManager: 알 수 없는 채널 '${channel}' (master|bgm|sfx)`);
    return this._vol[channel];
  }

  _effective(channel) { return this._vol.master * this._vol[channel]; }

  /** SFX 최종 볼륨 — Audio.volume 은 0~1 밖이면 예외를 던지므로 반드시 클램프한다. */
  _sfxVolume(gain) {
    const g = Number.isFinite(gain) ? gain : 1;
    return Math.min(1, Math.max(0, this._effective('sfx') * g));
  }

  /** SFX 인스턴스 1개 생성·재생 — playSfx/playKeyedSfx 공용 코어. 끝나거나 실패하면 추적에서 자동 해제. */
  _spawnSfx(src, gain, key) {
    let base = this._sfxCache.get(src);
    if (!base) { base = new Audio(src); base.preload = 'auto'; this._sfxCache.set(src, base); }
    const a = base.cloneNode(true);
    a._uiGain = Number.isFinite(gain) ? Math.min(1, Math.max(0, gain)) : 1;
    a.volume = this._sfxVolume(a._uiGain);
    a.muted = this._muted;
    this._sfxLive.add(a);
    a.addEventListener('ended', () => {
      this._sfxLive.delete(a);
      // 같은 key 를 새 인스턴스가 이미 가져갔으면 지우지 않는다(늦게 끝난 이전 소리가 새 것을 지우는 사고 방지)
      if (key != null && this._sfxKeyed.get(key) === a) this._sfxKeyed.delete(key);
    }, { once: true });
    a.play().catch((e) => {
      this._sfxLive.delete(a);
      if (key != null && this._sfxKeyed.get(key) === a) this._sfxKeyed.delete(key);
      console.warn('[SoundManager] SFX 재생 실패:', src, e);
    });
    return a;
  }

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

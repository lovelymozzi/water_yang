// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// 팝업 매니저 — 임의의 씬 contract 를 현재 화면 위에 오버레이로 띄운다.
// 규칙: 등장 = 스케일 업(작게→크게)으로 커지며 나타나고, 닫기 = 스케일 다운(크게→작게)으로 작아지며 사라진다.
// contract/scene-renderer 는 읽기 전용. SceneRenderer API + 런타임 스타일만 사용한다.
import { SceneRenderer } from './scene-renderer.js';

const Z_BACKDROP = 9000;
const Z_POPUP = 9001;
const OPEN_MS = 280;
const CLOSE_MS = 200;
const SCALE_FROM = 0.7;
const EASE_OUT_BACK = 'cubic-bezier(0.34,1.56,0.64,1)'; // 살짝 오버슈트하며 커짐
const EASE_IN = 'cubic-bezier(0.4,0,1,1)';

export class PopupManager {
  constructor(rendererOpts = {}) {
    this._rendererOpts = rendererOpts;
    this._renderer = null;
    this._backdrop = null;
    this._sceneId = null;
    this._unsubs = [];
    this._closing = false;
    this._opening = false; // contract fetch 대기 중 재호출(연타) 차단 — _renderer 는 fetch 후에야 세팅되므로 별도 플래그 필요
  }

  get isOpen() { return !!this._renderer; }

  /**
   * @param {string} contractUrl - 팝업 씬 contract 경로
   * @param {object} [opts]
   * @param {object} [opts.data] - renderer.update() 로 주입할 바인딩 데이터 (show 전에 주입되어 첫 페인트부터 반영)
   * @param {Object<string,Function>} [opts.on] - { eventName: handler } 이벤트 구독
   * @param {(renderer:SceneRenderer)=>void} [opts.after] - show/update 직후 후처리 (bindingKey 없는 텍스트 직접 채우기 등)
   */
  async open(contractUrl, { data = null, on = {}, after = null } = {}) {
    if (this._renderer || this._opening) { // 동시에 하나만 (fetch 대기 중 연타 포함)
      console.warn('[PopupManager] open 무시 — 이미 팝업이 열려 있거나 여는 중입니다:', contractUrl);
      return this;
    }
    this._opening = true;
    try {
      const resp = await fetch(contractUrl);
      if (!resp.ok) throw new Error(`PopupManager: contract 로드 실패(HTTP ${resp.status}): ${contractUrl}`);
      const contract = await resp.json();
      this._sceneId = contract.sceneId;

      // 별도 백드롭(딤) — 팝업 본체만 스케일하고 딤은 풀스크린 고정으로 페이드.
      const backdrop = document.createElement('div');
      backdrop.style.cssText =
        `position:fixed;inset:0;background:rgba(0,0,0,0.55);opacity:0;z-index:${Z_BACKDROP};`;
      document.body.appendChild(backdrop);
      this._backdrop = backdrop;

      const r = new SceneRenderer(document.body, this._rendererOpts);
      r.loadSync(contract);
      this._renderer = r;
      for (const [evt, fn] of Object.entries(on)) this._unsubs.push(r.on(evt, fn));

      if (data) r.update(data); // show() 전에 주입 — 첫 페인트부터 실제값 (디폴트 literal 플리커 방지)
      r.show();
      if (after) after(r);

      const root = document.getElementById(this._sceneId);
      if (!root) throw new Error(`PopupManager: 팝업 루트(#${this._sceneId})를 찾지 못했습니다.`);
      root.parentElement.style.zIndex = String(Z_POPUP); // .sr-fit 을 백드롭 위로
      root.style.background = 'transparent';              // contract 내장 딤 제거(백드롭으로 대체)
      root.style.transition = 'none';                     // 내장 opacity transition 과 충돌 방지
      root.style.transformOrigin = 'center center';

      backdrop.animate([{ opacity: 0 }, { opacity: 1 }], { duration: OPEN_MS, fill: 'forwards' });
      root.animate(
        [{ transform: `scale(${SCALE_FROM})`, opacity: 0 }, { transform: 'scale(1)', opacity: 1 }],
        { duration: OPEN_MS, easing: EASE_OUT_BACK, fill: 'forwards' }
      );
      return this;
    } finally {
      this._opening = false;
    }
  }

  async close() {
    if (this._closing || !this._renderer) return;
    this._closing = true;

    const root = document.getElementById(this._sceneId);
    const anims = [];
    if (root) {
      anims.push(root.animate(
        [{ transform: 'scale(1)', opacity: 1 }, { transform: `scale(${SCALE_FROM})`, opacity: 0 }],
        { duration: CLOSE_MS, easing: EASE_IN, fill: 'forwards' }
      ).finished);
    }
    anims.push(this._backdrop.animate(
      [{ opacity: 1 }, { opacity: 0 }], { duration: CLOSE_MS, fill: 'forwards' }
    ).finished);

    await Promise.all(anims);
    this._teardown();
  }

  _teardown() {
    this._unsubs.forEach(off => off());
    this._unsubs = [];
    this._renderer?.hide();
    this._renderer = null;
    if (this._backdrop?.parentNode) this._backdrop.parentNode.removeChild(this._backdrop);
    this._backdrop = null;
    this._sceneId = null;
    this._closing = false;
  }
}

// 튜토리얼 터치 힌트 — 암전 포커싱 + 안내 문구 + "여기를 누르세요" 손가락/파동.
// 좌표만 받아서 body 최상단 오버레이에 CSS 애니메이션으로 그린다. 씬/캐릭터 시스템과 무관하며
// 어느 화면에서도 그대로 재사용한다. 동시에 하나만 뜬다(둘 이상은 사용자 시선이 갈라져서 금지).
//
// ⚠ publish 산출물(읽기 전용) — ui-editor 가 저장 publish 마다 덮어쓴다. 게임 폴더에서 이 파일을
//   수정하면 다음 publish 때 사라진다. 색·크기·주기 튜닝은 configure() 로 게임 코드에서 한다.
//
//   await TutorialHint.step({ target: '#btn', text: '여기를 눌러 시작하세요' });  // 누를 때까지 대기
//   await TutorialHint.drag({ from: '#tile', to: '#slot', text: '여기로 끌어오세요' });  // 드래그 모션
//   TutorialHint.show('#btn');   // 손가락만 (암전·문구 없이)
//   TutorialHint.hide();         // 강제 종료 — 대기 중이던 step()/drag() 도 함께 풀린다
//   TutorialHint.configure({ dim: 0.6, cycle: 1400 });  // 첫 show/step 전에 호출

// 튜닝 값 전부 여기 모여 있고, 게임은 configure() 로만 바꾼다(파일 수정 금지 — 덮어쓰기로 소실).
// tipX/tipY 는 손끝이 이미지 어디인지(가로/세로 비율). 손 이미지를 교체하면 이 두 값만 다시 잰다 —
// 접점 정렬·회전 원점이 전부 이 값에서 파생된다. 기본 tutorial-hand.webp(181×173) 알파 실측:
// 최외곽 손끝 (0.039, 0.023) = 좌상단, 외곽선 두께만큼 안으로 넣어 손끝 살이 점에 닿게 한 값.
const cfg = {
    // 모듈 옆 vendor/ — publish 가 vendor 번들로 함께 복사하므로 게임 폴더 구조와 무관하게 맞는다.
    handSrc: new URL('vendor/tutorial-hand.webp', import.meta.url).href,
    tipX: 0.06,
    tipY: 0.045,
    handW: 78,     // 손 표시 폭(px). 390 캔버스 기준 — 뷰포트가 크게 다르면 configure 로 조정.
    ring: 66,      // 파동 최대 지름(px)
    dot: 14,       // 접점 표시 점 지름(px)
    cycle: 1700,   // 한 번 탭하고 쉬는 주기(ms)
    dragCycle: 2400, // 누르고 끌고 떼는 한 주기(ms) — 이동 구간이 있어 탭보다 길다
    dim: 0.74,     // 암전 농도
    feather: 14,   // 구멍 경계 그라데이션 폭(px)
    msgGap: 20,    // 구멍과 문구 사이 최소 간격(px)
    typeMs: 26,    // 글자 하나 타이핑 간격(ms)
    tapSlack: 30,  // 탭 판정 여유(px) — 구멍 반경보다 이만큼 바깥까지 탭을 인정(시각적 구멍 크기는 그대로)
};

/** 튜닝 오버라이드. CSS 는 첫 show/step 때 한 번 생성되므로 그 전에 호출한다. */
export function configure(opts) {
    Object.assign(cfg, opts);
}

function buildCss() {
    return `
.tut-hint{position:fixed;left:0;top:0;pointer-events:none;z-index:9999}
/* 암전은 엘리먼트 1개 + radial-gradient 구멍. SVG 마스크나 4분할 박스보다 짧고, 원점은
   커스텀 프로퍼티라 매 프레임 문자열을 다시 만들지 않는다. 클릭은 이 판이 전부 삼킨다. */
.tut-dim{position:fixed;inset:0;z-index:9998;pointer-events:auto;
  background:radial-gradient(circle var(--r,80px) at var(--tx,50%) var(--ty,50%),
    rgba(0,0,0,0) 0,rgba(0,0,0,0) calc(100% - ${cfg.feather}px),rgba(0,0,0,${cfg.dim}) 100%)}
.tut-msg{position:fixed;left:50%;transform:translateX(-50%);z-index:9999;pointer-events:none;
  box-sizing:border-box;width:min(330px,calc(100vw - 32px));padding:13px 16px;
  border-radius:12px;background:rgba(16,22,32,.94);border:1px solid rgba(255,255,255,.18);
  box-shadow:0 6px 20px rgba(0,0,0,.45);
  color:#fff;font-size:15px;line-height:1.45;text-align:center;white-space:pre-wrap;
  min-height:1.45em}
.tut-hint-ring{position:absolute;left:${-cfg.ring / 2}px;top:${-cfg.ring / 2}px;width:${cfg.ring}px;height:${cfg.ring}px;
  border-radius:50%;border:3px solid #fff;box-sizing:border-box;
  background:radial-gradient(circle,rgba(255,255,255,.30),rgba(255,255,255,0) 72%);
  /* 흰 띠를 어두운 1px 선으로 위아래 감싼다 — 흰 배경(밝은 카드)에서도 윤곽이 남는다. */
  box-shadow:0 0 0 1px rgba(0,0,0,.4),inset 0 0 0 1px rgba(0,0,0,.4),0 0 10px rgba(255,255,255,.55);
  /* both = 지연 중에도 0% 프레임(투명) 적용. 없으면 첫 사이클 전까지 큰 원이 그냥 떠 있다. */
  animation:tut-hint-ripple ${cfg.cycle}ms ease-out infinite both}
.tut-hint-dot{position:absolute;left:${-cfg.dot / 2}px;top:${-cfg.dot / 2}px;width:${cfg.dot}px;height:${cfg.dot}px;
  border-radius:50%;background:#fff;box-shadow:0 0 0 1.5px rgba(0,0,0,.4),0 0 8px rgba(255,255,255,.7);
  animation:tut-hint-dot ${cfg.cycle}ms ease-out infinite}
.tut-hint-hand{position:absolute;width:${cfg.handW}px;height:auto;
  filter:drop-shadow(0 3px 6px rgba(0,0,0,.45));
  transform-origin:${cfg.tipX * 100}% ${cfg.tipY * 100}%;  /* 손끝을 축으로 눌린다 — 접점이 밀리지 않게 */
  animation:tut-hint-tap ${cfg.cycle}ms cubic-bezier(.3,.7,.4,1) infinite}
/* 손가락 축(좌상단 방향)으로 물러났다 붙는다 — 화면에서 떨어질수록 작게(0.93), 닿을 때 원래 크기.
   축은 손끝 원점이라 접점은 프레임 내내 고정된다. */
@keyframes tut-hint-tap{
  0%{transform:translate(-11px,-11px) scale(.93)}
  16%,28%{transform:translate(0,0) scale(1)}
  46%,100%{transform:translate(-11px,-11px) scale(.93)}
}
@keyframes tut-hint-ripple{
  0%,15%{transform:scale(.18);opacity:0}
  19%{transform:scale(.26);opacity:.95}
  70%,100%{transform:scale(1);opacity:0}
}
/* 접점 점 — 파동이 다 사라진 쉬는 구간에도 남아서 "어디를" 누르는지는 항상 보인다. */
@keyframes tut-hint-dot{
  0%,15%{transform:scale(.75);opacity:.55}
  19%{transform:scale(1.25);opacity:1}
  60%,100%{transform:scale(.75);opacity:.55}
}
/* ── 드래그 모션 (.tut-drag) ────────────────────────────────────────────────
   이동은 transform 이 아니라 translate 속성으로 준다 — 누름(손)·파동(링)이 이미 transform 을
   쓰고 있어 채널이 겹치면 한쪽이 덮인다. 두 속성은 독립이라 한 요소에 둘 다 물릴 수 있다.
   이동량 --dx/--dy 는 place() 가 매 프레임 갱신하므로 출발/도착이 움직여도 따라간다. */
@keyframes tut-hint-travel{
  0%,20%{translate:0 0}
  75%,100%{translate:var(--dx,0) var(--dy,0)}
}
/* 접근 → 누름(12%) → 누른 채 이동 → 뗌(88%). 탭 키프레임과 달리 이동 구간 내내 눌러져 있다. */
@keyframes tut-hint-drag-hand{
  0%{transform:translate(-11px,-11px) scale(.93)}
  12%,80%{transform:translate(0,0) scale(1)}
  88%,100%{transform:translate(-11px,-11px) scale(.93)}
}
.tut-hint.tut-drag .tut-hint-ring{
  animation:tut-hint-ripple ${cfg.dragCycle}ms ease-out infinite both,
            tut-hint-travel ${cfg.dragCycle}ms ease-in-out infinite both}
.tut-hint.tut-drag .tut-hint-dot{
  animation:tut-hint-dot ${cfg.dragCycle}ms ease-out infinite,
            tut-hint-travel ${cfg.dragCycle}ms ease-in-out infinite both}
.tut-hint.tut-drag .tut-hint-hand{
  animation:tut-hint-drag-hand ${cfg.dragCycle}ms ease-out infinite both,
            tut-hint-travel ${cfg.dragCycle}ms ease-in-out infinite both}
/* 파동 3겹의 지연(inline animation-delay)은 이동 애니에도 걸려 겹마다 다른 위치로 흩어진다.
   드래그에서는 한 겹만 남긴다 — 첫 겹은 지연 0 이라 이동이 손과 정확히 맞물린다. */
.tut-hint.tut-drag .tut-hint-ring:nth-of-type(n+2){display:none}`;
}

let overlay = null;
let dim = null;
let msg = null;
let raf = 0;
let typer = 0;
// 현재 스텝: { el, radius, onTap } — el 은 요소 또는 {x,y}. place() 가 매 프레임 읽는다.
let cur = null;
let lastKey = '';

function ensureOverlay() {
    if (overlay) return overlay;
    const st = document.createElement('style');
    st.id = 'tut-hint-css';
    st.textContent = buildCss();
    document.head.appendChild(st);

    overlay = document.createElement('div');
    overlay.className = 'tut-hint';
    // 파동 3겹. 같은 주기라 지연을 줘도 손 탭과 위상이 영구히 맞물린다.
    overlay.innerHTML = [0, 220, 440].map(d =>
        `<div class="tut-hint-ring" style="animation-delay:${d}ms"></div>`).join('')
        + '<div class="tut-hint-dot"></div>'
        + `<img class="tut-hint-hand" src="${cfg.handSrc}" alt="">`;
    document.body.appendChild(overlay);
    return overlay;
}

function ensureDim() {
    if (dim) return;
    dim = document.createElement('div');
    dim.className = 'tut-dim';
    msg = document.createElement('div');
    msg.className = 'tut-msg';
    document.body.append(dim, msg);
    // 암전판이 화면 전체의 클릭을 삼킨다 — 구멍 안이면 통과시켜 타깃을 누르고, 밖이면 버린다.
    // 이래야 "그 버튼만" 이 진행 조건이 된다(구멍을 클릭 통과시키는 마스크 트릭이 필요 없다).
    dim.addEventListener('click', ev => {
        if (!cur) return;
        if (typer) { finishText(); return; }   // 타이핑 중 탭 = 문구 즉시 완성(진행은 아님)
        const p = point(cur.el);
        if (Math.hypot(ev.clientX - p.x, ev.clientY - p.y) > radiusOf(cur) + cfg.tapSlack) return;
        const el = cur.el;
        hide();                                // 대기 promise 도 여기서 함께 풀린다
        if (el.click) el.click();              // 게임의 원래 핸들러가 돌아야 다음 단계가 진행된다
    });
}

/** Element | CSS 선택자 | {x,y}(viewport 좌표) → 위치를 잴 수 있는 값. 못 찾으면 null. */
function resolveTarget(target, label) {
    const el = typeof target === 'string' ? document.querySelector(target) : target;
    if (!el || (!el.getBoundingClientRect && typeof el.x !== 'number')) {
        console.warn('[TutorialHint] ' + (label || '타깃') + '을(를) 못 찾음:', target);
        return null;
    }
    return el;
}

function point(el) {
    if (!el.getBoundingClientRect) return { x: el.x, y: el.y };
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
}

function radiusOf(step) {
    if (step.radius) return step.radius;
    const el = step.el;
    if (!el.getBoundingClientRect) return cfg.ring;
    const r = el.getBoundingClientRect();
    return Math.hypot(r.width, r.height) / 2 + 12;   // 사각 버튼을 감싸는 최소 원 + 여유
}

// 요소는 매 프레임 따라간다 — 스크롤·리사이즈·씬 전환·레이아웃 시프트로 타깃이 움직여도
// 힌트/구멍이 엉뚱한 곳에 남지 않는다. 값이 안 바뀌면 아무것도 건드리지 않는다.
function place() {
    if (!cur) return;                 // hide() 직후 남은 rAF 한 프레임
    const p = point(cur.el);
    const x = Math.round(p.x), y = Math.round(p.y);
    // 구멍(hx,hy,r): 탭이면 타깃 위. 드래그면 출발~도착을 한 원으로 덮는다 —
    // 구멍을 출발점에만 두면 손이 이동 중 암전 영역으로 들어가 사라진다.
    let hx = x, hy = y, r = Math.round(radiusOf(cur)), dx = 0, dy = 0;
    if (cur.to) {
        const q = point(cur.to);
        dx = Math.round(q.x - p.x); dy = Math.round(q.y - p.y);
        hx = Math.round(p.x + dx / 2); hy = Math.round(p.y + dy / 2);
        r = Math.round(Math.hypot(dx, dy) / 2 + radiusOf(cur));
    }
    const key = `${x},${y},${hx},${hy},${r},${dx},${dy},${msg ? msg.textContent.length : 0}`;
    if (key !== lastKey) {
        lastKey = key;
        if (overlay) {
            overlay.style.transform = `translate(${x}px,${y}px)`;
            if (cur.to) {
                overlay.style.setProperty('--dx', `${dx}px`);
                overlay.style.setProperty('--dy', `${dy}px`);
            }
        }
        if (dim) {
            dim.style.setProperty('--tx', `${hx}px`);
            dim.style.setProperty('--ty', `${hy}px`);
            dim.style.setProperty('--r', `${r}px`);
            // 기본은 화면 중앙. 구멍(탭 타깃·드래그 동선을 덮는 원)과 겹칠 때만 위/아래로 밀어낸다 —
            // 중앙에서 덜 밀리는 쪽 우선, 양쪽 다 안 들어가면 여유가 넓은 쪽 화면 끝에 붙인다.
            const vh = window.innerHeight, h = msg.offsetHeight;
            const mid = (vh - h) / 2;
            const above = hy - r - cfg.msgGap - h;   // 구멍 위에 붙는 top
            const below = hy + r + cfg.msgGap;       // 구멍 아래에 붙는 top
            let yPos = mid;
            if (mid < below && mid + h > hy - r - cfg.msgGap) { // 중앙 배치가 구멍과 겹침
                const fitA = above >= cfg.msgGap, fitB = below + h <= vh - cfg.msgGap;
                yPos = fitA && (!fitB || Math.abs(above - mid) <= Math.abs(below - mid)) ? above
                    : fitB ? below
                    : (hy - r >= vh - (hy + r) ? cfg.msgGap : vh - cfg.msgGap - h);
            }
            msg.style.top = Math.round(yPos) + 'px';
        }
    }
    // 좌표({x,y})만 받은 경우는 움직일 일이 없어 루프를 멈춘다 — 출발·도착 중 하나라도 요소면 계속 따라간다.
    const follows = cur.el.getBoundingClientRect || (cur.to && cur.to.getBoundingClientRect);
    raf = follows ? requestAnimationFrame(place) : 0;
}

function finishText() {
    clearInterval(typer);
    typer = 0;
    msg.textContent = cur.text;
    if (overlay) overlay.style.display = '';   // 문구가 다 나온 뒤에야 손가락이 나온다
}

/** target: Element | CSS 선택자 | {x,y} (viewport 좌표). 요소면 그 중심을 찍는다. */
export function show(target, to) {
    const el = resolveTarget(target);
    if (!el) return false;
    cur = { el, to: to || null, text: '' };
    const o = ensureOverlay();
    o.style.display = '';
    o.classList.toggle('tut-drag', !!cur.to);   // 드래그 키프레임 전환(이동 + 누른 채 유지)
    const hand = o.querySelector('.tut-hint-hand');
    // 손끝(TIP)이 타깃에 오도록 이미지 자체를 밀어둔다. 높이는 로드 뒤에나 알 수 있어 비율로 계산.
    const setOffset = () => {
        const h = hand.naturalWidth ? cfg.handW * hand.naturalHeight / hand.naturalWidth : cfg.handW;
        hand.style.left = `${-cfg.handW * cfg.tipX}px`;
        hand.style.top = `${-h * cfg.tipY}px`;
    };
    hand.complete ? setOffset() : hand.addEventListener('load', setOffset, { once: true });
    cancelAnimationFrame(raf);
    lastKey = '';
    place();
    return true;
}

/**
 * 한 단계: 타깃 주변만 밝히고(암전+구멍) 문구를 타이핑한 뒤, 그 타깃을 누를 때까지 기다린다.
 * 구멍 밖 입력은 전부 무시되므로 튜토리얼 순서가 깨지지 않는다.
 * @returns {Promise<void>} 타깃을 누르면 resolve (게임의 원래 클릭 핸들러도 함께 실행됨)
 */
export function step({ target, text = '', radius = 0 }) {
    return _begin({ target, text, radius });
}

/**
 * 드래그 단계: 출발에서 누르고 도착까지 끌었다 떼는 손 모션을 반복 재생한다.
 * 판정은 하지 않는다 — 어디서 어디로 끄는지도, 성공 시점도 게임이 정한다. 게임의 드래그 로직이
 * 성공하면 hide() 를 부르고, 그때 이 Promise 가 풀린다.
 * 탭 단계와 달리 암전판이 입력을 삼키지 않는다(삼키면 게임이 드래그를 못 받는다) — 게이팅 없음.
 * @param {{from:*, to:*, text?:string, radius?:number}} o from/to = Element | CSS 선택자 | {x,y}
 * @returns {Promise<void>} hide() 호출 시 resolve
 */
export function drag({ from, to, text = '', radius = 0 }) {
    const dest = resolveTarget(to, '도착 지점');
    return _begin({ target: from, text, radius, to: dest });
}

// step/drag 공통 진행부 — 암전·문구 타이핑·대기 promise. to 가 있으면 드래그(입력 통과) 모드.
function _begin({ target, text, radius, to }) {
    return new Promise(resolve => {
        if (!show(target, to)) return resolve();
        ensureDim();
        overlay.style.display = 'none';        // 문구 타이핑이 끝날 때까지 손가락은 숨김
        // 드래그는 암전하지 않는다 — 구멍이 출발~도착을 다 덮을 만큼 커지면 정작 어느 영역인지
        // 분간이 안 되고, 게이팅도 못 하므로(입력을 통과시켜야 게임이 드래그를 받는다) 암전이 할 일이 없다.
        // 문구·손 모션은 그대로. display:none 이면 입력도 통과하므로 pointer-events 를 따로 끌 필요가 없다.
        dim.style.display = to ? 'none' : '';
        msg.style.display = '';
        cur.radius = radius;
        cur.text = text;
        cur.onTap = resolve;
        // 암전판과 radius 는 show() 의 첫 place() 뒤에 정해진다 — 여기서 한 번 더 배치해
        // 구멍이 기본 자리·기본 반경으로 한 프레임 떴다가 튀는 깜빡임을 없앤다.
        cancelAnimationFrame(raf);
        lastKey = '';
        place();
        msg.textContent = '';
        let i = 0;
        typer = setInterval(() => {
            msg.textContent = text.slice(0, ++i);
            if (i >= text.length) finishText();
        }, cfg.typeMs);
        if (!text) finishText();
    });
}

/** 강제 종료. 대기 중이던 step()/drag() 의 Promise 도 함께 푼다(씬 이탈·게임의 완료 통지). */
export function hide() {
    const pending = cur && cur.onTap;
    cancelAnimationFrame(raf);
    clearInterval(typer);
    raf = typer = 0;
    cur = null;
    lastKey = '';
    if (overlay) overlay.style.display = 'none';
    if (dim) dim.style.display = msg.style.display = 'none';
    if (pending) pending();
}

export const TutorialHint = { show, hide, step, drag, configure };
export default TutorialHint;

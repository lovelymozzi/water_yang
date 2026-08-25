/**
 * SceneRenderer
 * Contract JSON을 읽어 게임 씬 DOM을 관리하는 클래스.
 *
 * Usage:
 *   import { SceneRenderer } from './scene-renderer.js';
 *   import contract from './scenes/main-menu.contract.json' assert { type: 'json' };
 *
 *   const renderer = new SceneRenderer(document.body);
 *   renderer.loadSync(contract);
 *   renderer.show();
 *   renderer.on('coin_btn_clicked', () => openShop());
 *   renderer.update({ player: { coins: 1500 } });
 */
function hexToRgba(hex, opacity) {
    const r = parseInt(hex.slice(1,3), 16);
    const g = parseInt(hex.slice(3,5), 16);
    const b = parseInt(hex.slice(5,7), 16);
    return `rgba(${r},${g},${b},${(opacity ?? 100) / 100})`;
}

// 텍스트 text-shadow 값(Y깊이 스택 + 소프트섀도우) 단일 소스.
function buildTextShadowValue(t) {
    const style = t.style || normalizeTextStyleModel(t);
    const depth = style.depth || {};
    const shadow = style.shadow || {};
    const layers = [];
    const ds = depth.size || 0;
    if (ds > 0) {
        const dc = depth.color || '#000000';
        for (let i = 1; i <= ds; i++) layers.push(`0 ${i}px 0 ${dc}`);
    }
    layers.push(`${shadow.x || 0}px ${shadow.y || 0}px ${shadow.blur || 0}px ${hexToRgba(shadow.color || '#000000', shadow.opacity ?? 0)}`);
    return layers.join(', ');
}

// 워드아트 곡선 배치 여부. curveType==='arc' 이고 곡률(curveAngle)이 0이 아닐 때만 곡선.
function isTextCurved(t) {
    return !!(t && t.curveType === 'arc' && Math.abs(t.curveAngle || 0) > 0);
}

// 텍스트 채움 그라데이션 값 단일 소스 — 평문/곡선 글자의 오버레이(applyTextGradientOverlay)가 소비.
// color(시작)→color2(끝), 기본 180deg=상→하. 비활성이면 ''.
// 정지점 25%~80%: 글리프는 줄박스(1.2em)의 대략 그 대역에만 그려진다(위=반레딩+ascent 여백,
// 아래=descent. Lilita One 등 디스플레이 폰트는 ascent 가 커서 더 아래로 깔림). 0~100% 그대로면
// 순색 구간이 빈 여백에 버려져 컬러2 쪽만 보이므로, 전환을 글리프 대역에 맞춰 5:5 체감으로 압축.
function textGradientValue(t, style) {
    const grad = (style || t.style || normalizeTextStyleModel(t)).gradient;
    if (!grad || !grad.enabled) return '';
    return `linear-gradient(${grad.angle ?? 180}deg,${t.color || '#fff'} 25%,${grad.color2 || '#ffffff'} 80%)`;
}

// 그라데이션 채움을 본체와 분리된 ::after 오버레이(이중 레이어)로 그린다.
// 한 요소에 합치면(background-clip:text + fill 투명) 채움이 배경층으로 내려가 스트로크 안쪽
// 절반을 덮어줄 불투명 채움이 사라지고(스트로크 침식) 그림자도 drop-shadow 체인 대체가 필요했다.
// → 본체 = 기존 경로 그대로 스트로크(paint-order 바깥 방사)+text-shadow(깊이/그림자),
//   ::after = 같은 글자를 채움만 클리핑해 정확히 위에 얹는다(스트로크/그림자 리셋).
// 글자 내용 동기화는 data-grad-text(content:attr) — 바인딩 갱신은 _applyBoundText 가 함께 쓴다.
function applyTextGradientOverlay(el, t, style) {
    const grad = textGradientValue(t, style);
    if (!grad) {
        if (el.dataset && el.dataset.gradText !== undefined) { delete el.dataset.gradText; el.style.removeProperty('--txt-grad'); }
        return false;
    }
    if (typeof document !== 'undefined' && !document.getElementById('ui-text-grad-overlay')) {
        const st = document.createElement('style');
        st.id = 'ui-text-grad-overlay';
        st.textContent = '[data-grad-text]{position:relative;}'
            + '[data-grad-text]::after{content:attr(data-grad-text);position:absolute;left:0;top:0;right:0;bottom:0;'
            + 'background-image:var(--txt-grad);-webkit-background-clip:text;background-clip:text;'
            // 줄 단위 타일링 — 여러 줄이 박스 전체에 그라데이션 한 번을 나눠 갖지 않고(윗줄=색1,
            // 아랫줄=색2 현상) 줄마다 풀 스펙트럼을 다시 시작한다. 1.2em = 이 코드베이스의 고정
            // line-height(1lh 미지원 브라우저 폴백; line-height 를 바꾸면 여기도 함께).
            + 'background-size:100% 1.2em;background-size:100% 1lh;background-repeat:repeat;'
            + 'color:transparent;-webkit-text-fill-color:transparent;-webkit-text-stroke-width:0;text-shadow:none;pointer-events:none;}';
        document.head.appendChild(st);
    }
    el.dataset.gradText = el.textContent || '';
    el.style.setProperty('--txt-grad', grad);
    return true;
}

// 텍스트 외관 CSS(폰트·색·외곽선·깊이/그림자) 단일 소스 — 배치(position/offset)는 호출측 몫.
// 레이어/컴포넌트 텍스트(_textCss)와 동적 탭바 레이블(buildNavTabBar)이 공유한다.
function textAppearanceCss(t, sx = 1) {
    const style = t.style || normalizeTextStyleModel(t);
    const strokeStyle = style.stroke || {};
    const stroke = (strokeStyle.width || 0) > 0 ? `-webkit-text-stroke:${strokeStyle.width}px ${strokeStyle.color || '#000'};paint-order:stroke fill;` : '';
    const fs = Math.round((t.fontSize || 14) * sx);
    const base = `font-size:${fs}px;font-weight:${t.fontWeight || 'bold'};font-family:${t.fontFamily || '"Lilita One",cursive'};color:${t.color || '#fff'};`;
    // 그라데이션 모드에서도 본체는 이 경로 그대로(불투명 채움=color1) — 채움 위 그라데이션은
    // applyTextGradientOverlay 의 ::after 오버레이가 담당한다(합치면 스트로크/그림자 페인트 순서 충돌).
    return `${base}text-shadow:${buildTextShadowValue(t)};${stroke}`;
}

// 워드아트 호/원형 배치: 텍스트 span을 글자별 자식 span으로 쪼개 원호 위에 회전 배치한다.
// 색·폰트·외곽선·그림자는 CSS 상속으로 자식에 자동 전파되므로 여기선 위치/회전만 담당.
// curve 미설정 시 아무 동작도 하지 않고 false 반환 → 호출측 기존 평문 경로 유지.
// 곡선 텍스트는 글자별 분할 구조라 바인딩(textContent 통째 교체)과 양립 불가 → 호출측에서 바인딩 차단.
function applyTextCurve(span, t, sx = 1) {
    if (!isTextCurved(t)) return false;
    const chars = Array.from(span.textContent || '');
    if (chars.length === 0) return false;

    const A = t.curveAngle;                 // 총 곡률(도). 양수=위 아치, 음수=아래 아치, ±360=원형
    const up = A >= 0;
    const absA = Math.abs(A);
    const stepDeg = absA / chars.length;    // 글자당 각도. 중앙정렬 위해 글자 중심을 -absA/2..+absA/2 에 배치
    const stepRad = stepDeg * Math.PI / 180;
    const fs = (t.fontSize || 14) * sx;
    // 글자 진행폭 ≈ 폰트크기*0.62. 반지름 = 진행폭 / 스텝각 → 곡률(각도)만으로 반지름 자동결정(겹침 방지).
    const advance = fs * 0.62;
    const r = stepRad > 0 ? Math.max(advance, advance / stepRad) : advance;
    // 0크기 부모 span(translate -50%,-50% → 원점=배치 기준점). 자식은 그 원점 기준으로 절대배치 후 회전.
    const originY = up ? `calc(50% + ${r}px)` : `calc(50% - ${r}px)`;

    span.textContent = '';
    chars.forEach((ch, i) => {
        const deg = -absA / 2 + stepDeg * (i + 0.5);
        const rot = up ? deg : -deg;
        const c = document.createElement('span');
        c.textContent = ch === ' ' ? ' ' : ch;
        c.style.cssText = `position:absolute;left:50%;top:50%;white-space:pre;transform:translate(-50%,-50%) rotate(${rot}deg);transform-origin:50% ${originY};`;
        // 채움 그라데이션: 부모 span 은 0크기라 글자별 오버레이로 재적용(글자마다 상하 그라데이션 = 워드아트 관례).
        // 스트로크/그림자는 부모에서 상속되고 오버레이가 그 위에 채움만 얹는다(오버레이 쪽에서 리셋).
        applyTextGradientOverlay(c, t);
        span.appendChild(c);
    });
    return true;
}

function depthGradientCss(hex, intensity) {
    intensity = (intensity === undefined ? 50 : intensity) / 100;
    const r = parseInt(hex.slice(1,3), 16);
    const g = parseInt(hex.slice(3,5), 16);
    const b = parseInt(hex.slice(5,7), 16);
    function adj(r,g,b,f) {
        const blended = 1 + (f - 1) * intensity;
        if (blended > 1) return [r+(255-r)*(blended-1), g+(255-g)*(blended-1), b+(255-b)*(blended-1)].map(v=>Math.min(255,Math.round(v)));
        return [r*blended, g*blended, b*blended].map(v=>Math.max(0,Math.round(v)));
    }
    function h(c) { return '#'+c.map(v=>v.toString(16).padStart(2,'0')).join(''); }
    return `linear-gradient(180deg,`+
        ` ${h(adj(r,g,b,0.72))} 0%,`+
        ` ${h(adj(r,g,b,1.30))} 38%,`+
        ` ${hex} 55%,`+
        ` ${h(adj(r,g,b,0.65))} 78%,`+
        ` ${h(adj(r,g,b,0.55))} 90%,`+
        ` ${h(adj(r,g,b,0.78))} 100%)`;
}

function conicRaysCss(bright, dim, count) {
    bright = bright || 'rgba(255,255,255,0.7)';
    dim = dim || 'rgba(215,215,215,0.48)';
    count = Math.max(2, count || 8);
    const seg = 360 / count;
    const stops = [];
    for (let i = 0; i < count; i++) {
        const b = i * seg;
        stops.push(
            `transparent ${b}deg`,
            `${bright} ${b + seg * 0.06}deg`,
            `${bright} ${b + seg * 0.28}deg`,
            `transparent ${b + seg * 0.33}deg`,
            `${dim} ${b + seg * 0.55}deg`,
            `${dim} ${b + seg * 0.78}deg`,
            `transparent ${b + seg * 0.83}deg`
        );
    }
    return `conic-gradient(${stops.join(',')})`;
}

// 텍스처 패턴 목록 (단일 소스). id = texture/<id>_large.webp 파일과 매칭.
const TEXTURE_PATTERNS = [
    { id: 'wood',   label: '🪵 우드' },
    { id: 'wood2',  label: '🪵 우드2' },
    { id: 'fabric', label: '🧵 패브릭' },
    { id: 'marble', label: '🪨 마블' },
    { id: 'metal',  label: '⚙️ 메탈' },
    { id: 'stone',  label: '🧱 스톤' },
];

function textureAssetPath(name) {
    const id = TEXTURE_PATTERNS.some(p => p.id === name) ? name : 'wood';
    return `texture/${id}_large.webp`;
}

// 컴포넌트 fill → CSS 선언문(들). 단일 소스: 런타임 렌더/에디터 캔버스/CSS export 공용.
// 반환값은 'prop:value;' 형태의 선언문 문자열(텍스처는 다중 선언).
// resolveAsset: 텍스처 이미지 경로 변환 함수(기본 항등). 색조는 color1 × 텍스처 multiply 합성.
function componentFillCss(fill, resolveAsset) {
    const resolve = resolveAsset || ((p) => p);
    switch (fill.type) {
        case 'none':            return 'background:transparent;';
        case 'solid':           return `background:${fill.color1 || '#4a90d9'};`;
        case 'radial-gradient': return `background:radial-gradient(circle,${fill.color1},${fill.color2});`;
        case 'conic-gradient':  return `background:${conicRaysCss(fill.color1, fill.color2, fill.rayCount)};`;
        case 'depth-gradient':  return `background:${depthGradientCss(fill.color1 || '#4a90d9', fill.depthIntensity)};`;
        case 'texture': {
            const sc = Math.max(8, fill.textureScale || 120);
            const url = resolve(textureAssetPath(fill.texture));
            return `background-color:${fill.color1 || '#4a90d9'};background-image:url('${url}');`
                + `background-size:${sc}px ${sc}px;background-repeat:repeat;background-blend-mode:multiply;`;
        }
        default:                return `background:linear-gradient(${fill.angle || 180}deg,${fill.color1 || '#4a90d9'},${fill.color2 || '#2e6ab4'});`;
    }
}

function ringMaskCss(innerPct, outerPct) {
    const i = innerPct == null ? 28 : innerPct;
    const o = outerPct == null ? 76 : outerPct;
    const span = Math.max(1, o - i);
    return `radial-gradient(circle, transparent 0%, transparent ${Math.max(0, i - 8)}%, white ${i}%, rgba(255,255,255,0.75) ${i + span * 0.17}%, rgba(255,255,255,0.45) ${i + span * 0.38}%, rgba(255,255,255,0.18) ${i + span * 0.60}%, rgba(255,255,255,0.05) ${i + span * 0.81}%, transparent ${o}%)`;
}

function normalizePressEffect(source, target = 'self') {
    return {
        type: 'press',
        source: { provider: 'internal', name: 'press' },
        enabled: !!source.pressEnabled,
        target,
        trigger: 'pointer',
        params: {
            transitionMs: source.pressTransition || 100,
            brightness: source.pressBrightness ?? 95,
            scale: source.pressScale ?? 95,
            useDepthOffset: !!source.depthEnabled,
        },
    };
}

function normalizeSpinEffect(source, target = 'self') {
    const spin = source.spinAnimation || {};
    return {
        type: 'spin',
        source: { provider: 'internal', name: 'spin' },
        enabled: !!spin.enabled,
        target,
        timing: {
            durationMs: (spin.duration || 10) * 1000,
            easing: 'linear',
            iteration: 'infinite',
        },
        params: {
            direction: spin.direction === 'ccw' ? 'ccw' : 'cw',
        },
    };
}

// ── 셀프호스팅 vendor 해석 ──────────────────────────────────────────────────
// publish 는 이 모듈 파일 옆에 vendor/(웹폰트·이펙트 CSS·confetti)를 함께 배포한다 — 로컬 우선, CDN 은 폴백.
// 에디터 play iframe 은 이 소스를 classic script 로 인라인하며 import.meta 를 문자열 치환으로 제거한다
// (ui-editor.html 의 _sceneRendererSource 로딩부 참조). 그 경우 문서 base 기준 'vendor/…' 상대경로를
// 쓴다(에디터 서버 루트에 vendor/ 존재. srcdoc iframe 은 부모 문서의 base 를 상속).
const MODULE_BASE = (() => { try { return new URL('.', import.meta.url).href; } catch (e) { return null; } })();
function vendorUrl(rel) { return (MODULE_BASE || '') + 'vendor/' + rel; }

const CSS_EFFECT_PROVIDER_STYLES = {
    'animate.css': { local: 'animate.min.css', cdn: 'https://cdn.jsdelivr.net/npm/animate.css@4.1.1/animate.min.css' },
};

const EFFECT_PROVIDER_SCRIPTS = {
    'canvas-confetti': { local: 'confetti.browser.min.js', cdn: 'https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.4/dist/confetti.browser.min.js' },
};

/** stylesheet <link> 를 로컬 vendor 우선으로 로드, 실패 시 CDN 으로 1회 폴백. _loadPromise 를 link 에 심는다(reveal 게이트 공용). */
function loadStylesheetWithFallback(link, localHref, cdnHref) {
    link._loadPromise = new Promise(resolve => {
        let triedCdn = false;
        link.onload = () => resolve(true);
        link.onerror = () => {
            if (triedCdn || !cdnHref) { resolve(false); return; }
            triedCdn = true;
            console.warn('[SceneRenderer] 로컬 vendor 스타일 로드 실패 — CDN 폴백:', localHref, '→', cdnHref);
            link.href = cdnHref; // href 교체 시 재로드됨
        };
        link.href = localHref;
    });
    return link._loadPromise;
}

/** <script> 를 로컬 vendor 우선으로 로드, 실패 시 새 엘리먼트로 CDN 폴백(스크립트는 src 교체 재실행이 안 되므로 재생성). */
function loadScriptWithFallback(id, localSrc, cdnSrc) {
    return new Promise(resolve => {
        const mk = (src, onFail) => {
            const s = document.createElement('script');
            s.id = id;
            s.src = src;
            s.async = true;
            s.onload = () => resolve(true);
            s.onerror = () => { s.remove(); onFail(); };
            document.head.appendChild(s);
        };
        mk(localSrc, () => {
            console.warn('[SceneRenderer] 로컬 vendor 스크립트 로드 실패 — CDN 폴백:', localSrc, '→', cdnSrc,
                '| 실제 요청 URL:', new URL(localSrc, document.baseURI).href, '| baseURI:', document.baseURI);
            mk(cdnSrc, () => resolve(false));
        });
    });
}

// show() 첫 공개를 렌더 리소스(이펙트 CSS·웹폰트) 준비까지 최대 이만큼 지연.
// 초과 시 경고 로그 후 그냥 공개(네트워크 불량으로 씬이 영영 안 뜨는 것 방지).
const RENDER_RESOURCE_TIMEOUT_MS = 2000;

// show() 후 배선 자가진단(_auditFlowWiring)까지의 유예 — 게임이 show() 직후에 구독하는
// 코드(권장은 show 전이지만 흔한 패턴)를 오경보 없이 수용하기 위한 지연.
const WIRING_AUDIT_DELAY_MS = 1500;

const CSS_ANIMATION_PRESETS = [
    { id: 'fade-in', label: 'Fade In', group: 'Appear', provider: 'animate.css', className: 'animate__fadeIn', phase: 'enter', durationMs: 700 },
    { id: 'fade-in-up', label: 'Fade In Up', group: 'Appear', provider: 'animate.css', className: 'animate__fadeInUp', phase: 'enter', durationMs: 700 },
    { id: 'fade-in-down', label: 'Fade In Down', group: 'Appear', provider: 'animate.css', className: 'animate__fadeInDown', phase: 'enter', durationMs: 700 },
    { id: 'fade-in-left', label: 'Fade In Left', group: 'Appear', provider: 'animate.css', className: 'animate__fadeInLeft', phase: 'enter', durationMs: 700 },
    { id: 'fade-in-right', label: 'Fade In Right', group: 'Appear', provider: 'animate.css', className: 'animate__fadeInRight', phase: 'enter', durationMs: 700 },
    { id: 'zoom-in', label: 'Zoom In', group: 'Appear', provider: 'animate.css', className: 'animate__zoomIn', phase: 'enter', durationMs: 650 },
    { id: 'zoom-in-up', label: 'Zoom In Up', group: 'Appear', provider: 'animate.css', className: 'animate__zoomInUp', phase: 'enter', durationMs: 750 },
    { id: 'zoom-in-down', label: 'Zoom In Down', group: 'Appear', provider: 'animate.css', className: 'animate__zoomInDown', phase: 'enter', durationMs: 750 },
    { id: 'bounce-in', label: 'Bounce In', group: 'Appear', provider: 'animate.css', className: 'animate__bounceIn', phase: 'enter', durationMs: 850 },
    { id: 'bounce-in-up', label: 'Bounce In Up', group: 'Appear', provider: 'animate.css', className: 'animate__bounceInUp', phase: 'enter', durationMs: 850 },
    { id: 'back-in-down', label: 'Back In Down', group: 'Appear', provider: 'animate.css', className: 'animate__backInDown', phase: 'enter', durationMs: 800 },
    { id: 'back-in-up', label: 'Back In Up', group: 'Appear', provider: 'animate.css', className: 'animate__backInUp', phase: 'enter', durationMs: 800 },
    { id: 'flip-in-x', label: 'Flip In X', group: 'Appear', provider: 'animate.css', className: 'animate__flipInX', phase: 'enter', durationMs: 800 },
    { id: 'flip-in-y', label: 'Flip In Y', group: 'Appear', provider: 'animate.css', className: 'animate__flipInY', phase: 'enter', durationMs: 800 },
    { id: 'light-speed-in', label: 'Light Speed In', group: 'Appear', provider: 'animate.css', className: 'animate__lightSpeedInRight', phase: 'enter', durationMs: 750 },
    { id: 'rotate-in', label: 'Rotate In', group: 'Appear', provider: 'animate.css', className: 'animate__rotateIn', phase: 'enter', durationMs: 750 },
    { id: 'fade-out', label: 'Fade Out', group: 'Disappear', provider: 'animate.css', className: 'animate__fadeOut', phase: 'exit', durationMs: 600 },
    { id: 'fade-out-up', label: 'Fade Out Up', group: 'Disappear', provider: 'animate.css', className: 'animate__fadeOutUp', phase: 'exit', durationMs: 650 },
    { id: 'fade-out-down', label: 'Fade Out Down', group: 'Disappear', provider: 'animate.css', className: 'animate__fadeOutDown', phase: 'exit', durationMs: 650 },
    { id: 'zoom-out', label: 'Zoom Out', group: 'Disappear', provider: 'animate.css', className: 'animate__zoomOut', phase: 'exit', durationMs: 600 },
    { id: 'bounce-out', label: 'Bounce Out', group: 'Disappear', provider: 'animate.css', className: 'animate__bounceOut', phase: 'exit', durationMs: 750 },
    { id: 'back-out-down', label: 'Back Out Down', group: 'Disappear', provider: 'animate.css', className: 'animate__backOutDown', phase: 'exit', durationMs: 750 },
    { id: 'flip-out-x', label: 'Flip Out X', group: 'Disappear', provider: 'animate.css', className: 'animate__flipOutX', phase: 'exit', durationMs: 700 },
    { id: 'bounce', label: 'Bounce', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__bounce', phase: 'attention', durationMs: 900 },
    { id: 'pulse', label: 'Pulse', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__pulse', phase: 'attention', durationMs: 800 },
    { id: 'heart-beat', label: 'Heart Beat', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__heartBeat', phase: 'attention', durationMs: 1000 },
    { id: 'tada', label: 'Tada', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__tada', phase: 'attention', durationMs: 900 },
    { id: 'rubber-band', label: 'Rubber Band', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__rubberBand', phase: 'attention', durationMs: 900 },
    { id: 'jello', label: 'Jello', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__jello', phase: 'attention', durationMs: 900 },
    { id: 'wobble', label: 'Wobble', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__wobble', phase: 'attention', durationMs: 900 },
    { id: 'swing', label: 'Swing', group: 'Cute / Attention', provider: 'animate.css', className: 'animate__swing', phase: 'attention', durationMs: 900 },
    // 점멸(fade in-out) — 타임라인에서 defaultLoop 로 추가 즉시 무한 반복(레일 프리셋 매핑 참조).
    // className 은 자체 키프레임(1사이클 = 1회 점멸). animate__flash 는 1사이클에 2번 깜빡인다.
    { id: 'flash', label: 'Flash (점멸)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-blink-once', phase: 'attention', durationMs: 1000, defaultLoop: true },
    // 자체 키프레임(ensureLocalCssAnimationKeyframes) — 수축+떨림 후 터지는 연출 2종
    { id: 'charge-pop', label: 'Charge Pop (모았다 빵)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-charge-pop', phase: 'attention', durationMs: 1300 },
    { id: 'squash-jump', label: 'Squash Jump (움츠렸다 점프)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-squash-jump', phase: 'attention', durationMs: 1400 },
    // squash-jump 2단 분리 — crouch(눌린 자세로 끝, fill 유지)→[이미지 교체]→launch(눌린 자세에서 점프 착지)
    { id: 'squash-crouch', label: 'Squash Crouch (움츠리기)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-squash-crouch', phase: 'attention', durationMs: 600 },
    { id: 'squash-launch', label: 'Squash Launch (점프 착지)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-squash-launch', phase: 'attention', durationMs: 900 },
    // 제자리 360° 회전 — 컴포넌트 전용이던 spinAnimation(ui-spin)을 이펙트로도 노출(이미지/스프라이트 포함).
    // 끊김 없이 돌리려면 Loop 켜고 Loop delay 를 0 으로.
    { id: 'spin-360', label: 'Spin 360 (제자리 회전)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-spin-cw', phase: 'attention', durationMs: 2000, defaultLoop: true },
    { id: 'spin-360-ccw', label: 'Spin 360 ◀ (역방향)', group: 'Cute / Attention', provider: 'animate.css', className: 'ui-spin-ccw', phase: 'attention', durationMs: 2000, defaultLoop: true },
];

function getCssAnimationPreset(presetId) {
    return CSS_ANIMATION_PRESETS.find(p => p.id === presetId) || null;
}

function normalizeCssAnimationEffect(source, target = 'self') {
    const cfg = source.cssAnimation || {};
    const preset = getCssAnimationPreset(cfg.presetId || 'bounce-in');
    return {
        type: 'css-animation',
        source: {
            provider: preset?.provider || 'animate.css',
            name: preset?.id || '',
            className: preset?.className || '',
        },
        enabled: !!cfg.enabled && !!preset,
        target,
        trigger: cfg.trigger || 'mount',
        timing: {
            durationMs: Math.round((cfg.duration || ((preset?.durationMs || 800) / 1000)) * 1000),
            delayMs: Math.round((cfg.delay || 0) * 1000),
            iteration: cfg.loop ? 1 : Math.max(1, parseInt(cfg.repeat || 1, 10)),
            loopDelayMs: Math.round((cfg.loopDelay ?? 0.6) * 1000),
        },
        params: {
            presetId: preset?.id || '',
            group: preset?.group || '',
            phase: preset?.phase || 'attention',
            className: preset?.className || '',
            baseClass: 'animate__animated',
            loop: !!cfg.loop,
        },
    };
}

// 프리셋 정체성: template = 발사 패턴(물리)이며 프리셋마다 실제 움직임이 달라야 한다.
// 색/모양만 다른 변형(재스킨)은 금지 — canvas-confetti 레시피는 playParticleEffect 참조.
//  - sparkle-burst(burst): 요소 중심에서 사방 방사형 폭발, 빠르고 짧게 낙하
//  - sparkle-halo(halo): 무중력 링 — 입자가 천천히 확장하며 떠다니다 소멸
//  - reward-pop(confetti): 위로 쏘아올린 색종이가 포물선으로 낙하
//  - magic-trail(stream): 시간차 다발 방출로 위로 솟는 연속 스트림
//  - soft-glitter(fall): 요소 상단 폭 전체에서 반짝이가 흩날리며 낙하
const PARTICLE_EFFECT_PRESETS = [
    { id: 'ambient-sparkle-aura', label: 'Ambient Sparkle Aura', group: 'Sparkle / Halo', provider: 'internal', template: 'ambient-aura', count: 18, auraWidth: 140, auraHeight: 140, speedMin: 0, speedMax: 0, sizeMin: 0.45, sizeMax: 0.9, spread: 360, loop: true },
    //  - healing-aura(내부 반복형): 발밑에서 피어오르는 녹빛 세로 광선 + 십자가 — RPG 힐 이펙트
    { id: 'healing-aura', label: 'Healing Aura', group: 'Sparkle / Halo', provider: 'internal', template: 'healing-aura', count: 26, auraWidth: 150, auraHeight: 160, speedMin: 0, speedMax: 0, sizeMin: 0.5, sizeMax: 1.1, spread: 0, loop: true },
    //  - treasure-glow(내부 반복형): 바닥 중심에 고정된 금빛 광선이 부채꼴로 일렁이고 반짝임이 피어오르는 보물상자 개봉 광채
    { id: 'treasure-glow', label: 'Treasure Glow (보물 광채)', group: 'Sparkle / Halo', provider: 'internal', template: 'treasure-glow', count: 30, auraWidth: 150, auraHeight: 170, speedMin: 0, speedMax: 0, sizeMin: 0.6, sizeMax: 1.2, spread: 44, loop: true },
    //  - warp-streaks(내부 반복형): 얇은 빛줄기가 중심에서 가속하며 통째로 날아가는 1인칭 하이퍼스페이스
    { id: 'warp-streaks', label: 'Warp Streaks (워프)', group: 'Sparkle / Halo', provider: 'internal', template: 'warp-streaks', count: 60, auraWidth: 100, auraHeight: 100, speedMin: 0, speedMax: 0, sizeMin: 1, sizeMax: 1, spread: 0, loop: true, colors: ['#ffffff', '#cfe4ff', '#9ec6ff'] },
    //  - manga-focus-lines(내부 반복형): 바깥은 화면 밖에 고정, 안쪽 뾰족한 끝만 물러나며 구멍이 벌어지는 만화 집중선 줌인
    { id: 'manga-focus-lines', label: 'Manga Focus Lines (집중선)', group: 'Sparkle / Halo', provider: 'internal', template: 'manga-focus-lines', count: 40, auraWidth: 100, auraHeight: 100, speedMin: 0, speedMax: 0, sizeMin: 1, sizeMax: 1, spread: 0, loop: true, colors: ['rgba(255,255,255,0.95)', 'rgba(228,240,255,0.8)'] },
    { id: 'sparkle-burst', label: 'Sparkle Burst', group: 'Sparkle / Halo', provider: 'canvas-confetti', template: 'burst', count: 36, speedMin: 200, speedMax: 420, sizeMin: 0.8, sizeMax: 1.6, spread: 360, lifetimeMin: 0.5, lifetimeMax: 0.9, colors: ['#ffd700', '#ffb300', '#fff3b0'], shapes: ['star'] },
    { id: 'sparkle-halo', label: 'Sparkle Halo', group: 'Sparkle / Halo', provider: 'canvas-confetti', template: 'halo', count: 24, speedMin: 30, speedMax: 80, sizeMin: 0.45, sizeMax: 0.9, spread: 360, lifetimeMin: 1.6, lifetimeMax: 2.4, colors: ['#ffffff', '#cfe8ff', '#9ad8ff'], shapes: ['circle', 'star'] },
    { id: 'reward-pop', label: 'Reward Pop', group: 'Sparkle / Halo', provider: 'canvas-confetti', template: 'confetti', count: 42, speedMin: 180, speedMax: 420, sizeMin: 0.7, sizeMax: 1.2, spread: 80, lifetimeMin: 1.6, lifetimeMax: 2.2 },
    { id: 'magic-trail', label: 'Magic Trail', group: 'Sparkle / Halo', provider: 'canvas-confetti', template: 'stream', count: 28, speedMin: 90, speedMax: 180, sizeMin: 0.5, sizeMax: 1.0, spread: 30, lifetimeMin: 1.0, lifetimeMax: 1.6, colors: ['#b26bff', '#5efce8', '#8a5cf6'], shapes: ['star', 'circle'] },
    { id: 'soft-glitter', label: 'Soft Glitter', group: 'Sparkle / Halo', provider: 'canvas-confetti', template: 'fall', count: 22, speedMin: 8, speedMax: 40, sizeMin: 0.25, sizeMax: 0.55, spread: 360, lifetimeMin: 1.6, lifetimeMax: 2.6, colors: ['#ffd6e8', '#ffffff', '#ffe9a8'], shapes: ['circle'] },
];

function getParticleEffectPreset(presetId) {
    return PARTICLE_EFFECT_PRESETS.find(p => p.id === presetId) || null;
}

function normalizeParticleEffect(source, target = 'self') {
    const cfg = source.particleEffect || {};
    const preset = getParticleEffectPreset(cfg.presetId || 'sparkle-burst');
    return {
        type: 'particle-effect',
        source: {
            provider: preset?.provider || 'canvas-confetti',
            name: preset?.id || '',
            template: preset?.template || 'burst',
        },
        enabled: !!cfg.enabled && !!preset,
        target,
        trigger: cfg.trigger || 'mount',
        params: {
            presetId: preset?.id || '',
            group: preset?.group || '',
            count: cfg.count ?? preset?.count ?? 30,
            speedMin: cfg.speedMin ?? preset?.speedMin ?? 50,
            speedMax: cfg.speedMax ?? preset?.speedMax ?? 260,
            sizeMin: cfg.sizeMin ?? preset?.sizeMin ?? 0.6,
            sizeMax: cfg.sizeMax ?? preset?.sizeMax ?? 1.2,
            spread: cfg.spread ?? preset?.spread ?? 70,
            auraWidth: cfg.auraWidth ?? preset?.auraWidth ?? 140,
            auraHeight: cfg.auraHeight ?? preset?.auraHeight ?? 140,
            loop: cfg.loop ?? !!preset?.loop,
            // 프리셋 정체성(색/모양/수명) — 사용자 조절 슬라이더 없음, 프리셋 고유값
            colors: cfg.colors ?? preset?.colors ?? null,
            shapes: cfg.shapes ?? preset?.shapes ?? null,
            lifetimeMin: cfg.lifetimeMin ?? preset?.lifetimeMin ?? null,
            lifetimeMax: cfg.lifetimeMax ?? preset?.lifetimeMax ?? null,
        },
    };
}

function normalizeComponentVisualModel(visual) {
    const v = visual || {};
    return {
        visualModel: {
            shape: {
                type: v.shapeType || 'rectangle',
                width: v.width || 100,
                height: v.height || 40,
                radius: v.borderRadius || 0,
                notch: v.ribbonNotch ?? 20,
                hollowThickness: v.hollowThickness || 8,
            },
            fill: {
                type: v.bgType || 'linear-gradient',
                color1: v.bgColor1 || '#4a90d9',
                color2: v.bgColor2 || '#2e6ab4',
                angle: v.gradientAngle || 180,
                depthIntensity: v.depthIntensity ?? 50,
                rayCount: v.rayCount || 8,
                texture: v.bgTexture || 'wood',
                textureScale: v.bgTextureScale || 120,
            },
            border: {
                width: v.borderWidth || 0,
                color: v.borderColor || '#ffffff',
                // outline = border 바깥 외곽 링(box-shadow spread). 캔디버튼의 '금테 밖 진초록 테두리'.
                outlineWidth: v.outlineWidth || 0,
                outlineColor: v.outlineColor || '#1e4a80',
            },
            // bevel = 각진 입체(캔디버튼): 경사면(바탕 fill) 위에 평탄한 눌림면을 얹는다.
            // 비대칭 인셋(top/side/bottom)으로 조명 방향 표현, softness = 면 접촉 그림자 blur.
            bevel: {
                enabled: !!v.bevelEnabled,
                top: v.bevelTop ?? 7,
                side: v.bevelSide ?? 8,
                bottom: v.bevelBottom ?? 12,
                color: v.bevelColor || v.bgColor1 || '#4a90d9',
                softness: v.bevelSoftness ?? 6,
            },
            shadows: [
                {
                    type: 'depth-edge',
                    enabled: !!v.depthEnabled,
                    size: v.depthSize || 0,
                    color: v.depthColor || '#000000',
                },
                {
                    type: 'outer',
                    enabled: !!v.outerShadowEnabled,
                    x: v.outerShadowX || 0,
                    y: v.outerShadowY ?? 4,
                    blur: v.outerShadowBlur ?? 8,
                    color: v.outerShadowColor || '#000000',
                    opacity: v.outerShadowOpacity ?? 30,
                },
                {
                    type: 'inner',
                    enabled: !!v.innerShadowEnabled,
                    x: v.innerShadowX || 0,
                    y: v.innerShadowY ?? 2,
                    blur: v.innerShadowBlur ?? 4,
                    color: v.innerShadowColor || '#ffffff',
                    opacity: v.innerShadowOpacity ?? 20,
                },
                {
                    // gloss = 상단 곡면 하이라이트(inset, border-radius 를 따라 좌상~우상을 감쌈).
                    // inner shadow 와 별도 슬롯 — 하이라이트(위)와 내부 음영(아래)을 동시에 쓰기 위함.
                    type: 'gloss',
                    enabled: !!v.glossEnabled,
                    size: v.glossSize ?? 10,
                    blur: v.glossBlur ?? 8,
                    color: v.glossColor || '#ffffff',
                    opacity: v.glossOpacity ?? 45,
                },
            ],
            mask: {
                type: 'ring-fade',
                enabled: !!v.maskEnabled,
                innerPct: v.maskInnerPct ?? 28,
                outerPct: v.maskOuterPct ?? 76,
            },
        },
        effects: [
            normalizePressEffect(v),
            normalizeSpinEffect(v),
            normalizeCssAnimationEffect(v),
            normalizeParticleEffect(v),
            normalizeShineEffect(v),
        ],
    };
}

function normalizeTextStyleModel(text) {
    const t = text || {};
    return {
        // 채움 그라데이션 — 기본 각도 180 = 상→하(배경 그라데이션과 동일 규약). color(위)→colorGrad2(아래).
        gradient: {
            enabled: !!t.colorGradEnabled,
            color2: t.colorGrad2 || '#ffffff',
            angle: t.colorGradAngle ?? 180,
        },
        stroke: {
            width: t.textStrokeWidth || 0,
            color: t.textStrokeColor || '#000000',
        },
        depth: {
            size: t.textDepthSize || 0,
            color: t.textDepthColor || '#000000',
        },
        shadow: {
            x: t.textShadowX || 0,
            y: t.textShadowY || 0,
            blur: t.textShadowBlur || 0,
            color: t.textShadowColor || '#000000',
            opacity: t.textShadowOpacity ?? 0,
        },
    };
}

function normalizeImageStyleModel(imageLike) {
    const im = imageLike || {};
    return {
        shadow: {
            enabled: !!im.shadowEnabled,
            x: im.shadowX || 0,
            y: im.shadowY ?? 4,
            blur: im.shadowBlur ?? 8,
            color: im.shadowColor || '#000000',
            opacity: im.shadowOpacity ?? 50,
        },
        tint: {
            mode: im.tintMode || 'off',   // 'off' | 'tint'(색조,명암유지) | 'overlay'(덧입히기,불투명 페인트)
            color: im.tintColor || '#ff3b30',
            strength: im.tintStrength ?? 100,
        },
        // 비율: false(기본)=원본 비율 고정(contain), true=width/height 대로 늘리기(fill, 왜곡 허용)
        stretch: !!im.stretch,
        // 9-slice: 모서리는 원본 px 유지, 변/중앙만 늘어남. 값은 원본 이미지 px 기준(유니티 spriteBorder 와 동일 좌표계).
        // scale = 모서리 표시 배율(유니티 pixelsPerUnitMultiplier 의 역수 대응) — 박스가 원본보다 축소 배치될 때 모서리도 같이 줄임
        slice: {
            enabled: !!im.sliceEnabled,
            left: im.sliceL || 0, top: im.sliceT || 0, right: im.sliceR || 0, bottom: im.sliceB || 0,
            scale: im.sliceScale || 1,
            repeat: im.sliceRepeat === 'tile' ? 'tile' : 'stretch',   // 변/중앙: 늘리기(기본) | 타일 반복(유니티 Tiled)
        },
    };
}

// 9-slice 기하 계산 단일 소스 — 렌더 CSS 생성 / 진단 로그 / 편집기 경고·권장값이 모두 이걸 쓴다.
// slice(t,r,b,l) = 원본에서 잘라낼 px(불변), bw = 화면상 모서리 크기(slice × sliceScale × 렌더 스케일 × 클램프).
// 클램프: 박스가 모서리 합보다 작으면 모서리를 비례 축소한다. 유니티 Image.GetAdjustedBorders 와 동일하게
// '축별 독립'(가로가 모자라면 L/R 만, 세로가 모자라면 T/B 만) — CSS border 는 box-sizing:border-box 여도
// 지정폭 이하로 줄지 않아, 클램프 없이는 박스가 border 합계 밑으로 못 내려가 부풀어 보인다.
// natW/natH(원본 px)를 주면 CSS 스펙의 '중앙·변 비어짐' 조건까지 판정한다(렌더 경로는 원본 크기를 모르므로 생략).
// @returns {{s, bw, fx, fy, contentW, contentH, emptyX, emptyY, collapsed}}
function sliceGeometry(sl, sx, sy, boxW, boxH, natW, natH) {
    const s = {
        t: Math.max(0, sl?.top || 0), r: Math.max(0, sl?.right || 0),
        b: Math.max(0, sl?.bottom || 0), l: Math.max(0, sl?.left || 0),
    };
    const sc = sl?.scale || 1;
    const sumX = (s.l + s.r) * sc * sx, sumY = (s.t + s.b) * sc * sy;
    const fx = boxW > 0 && sumX > boxW ? boxW / sumX : 1;
    const fy = boxH > 0 && sumY > boxH ? boxH / sumY : 1;
    const rx = fx < 1 ? Math.floor : Math.round;   // 클램프 시 내림 — 반올림으로 합계가 박스를 1px 넘는 것 방지
    const ry = fy < 1 ? Math.floor : Math.round;
    const bw = {
        t: ry(s.t * sc * sy * fy), r: rx(s.r * sc * sx * fx),
        b: ry(s.b * sc * sy * fy), l: rx(s.l * sc * sx * fx),
    };
    const contentW = boxW > 0 ? boxW - bw.l - bw.r : null;   // 중앙/상하변이 차지할 폭
    const contentH = boxH > 0 ? boxH - bw.t - bw.b : null;
    // CSS 스펙: 마주보는 slice 합이 원본 크기 '이상'이면 그 축의 변 2개 + 중앙을 아예 안 그린다(투명 취급).
    // 양축 모두 해당하면 결과가 정확히 모서리 4개만 남는다. 유니티에는 없는 규칙(유니티는 경계 픽셀을 늘려 채움).
    const emptyX = natW > 0 && s.l + s.r >= natW;
    const emptyY = natH > 0 && s.t + s.b >= natH;
    return {
        s, bw, fx, fy, contentW, contentH, emptyX, emptyY,
        collapsed: !!(emptyX || emptyY || contentW <= 0 || contentH <= 0),
    };
}

// 9-slice 렌더용 CSS 프래그먼트. <img> 는 콘텐츠(원본 이미지)가 border-image 위에 겹쳐 그려지므로
// slice 가 켜진 이미지는 호출부에서 <div> 로 만들고 이 프래그먼트를 cssText 에 더한다.
// fill = 중앙을 그린다(유니티 Image 의 Fill Center 와 동일). 기하 계산은 sliceGeometry 단일 소스.
// forMask=true 면 동일 기하의 -webkit-mask-box-image 롱핸드를 반환 — 오버레이(shine 등)를
// 9-slice 렌더 결과와 똑같은 알파 실루엣으로 잘라낼 때 사용(Chromium 전용, 미지원 브라우저는 무시되어 현행 유지).
function imageSliceCssText(style, src, sx, sy, boxW, boxH, forMask = false) {
    const sl = style?.slice;
    if (!sl?.enabled || !src) return '';
    const g = sliceGeometry(sl, sx, sy, boxW, boxH);
    const rep = sl.repeat === 'tile' ? 'round' : 'stretch';   // round = 정수 배로 맞춰 타일(끊김 없음)
    if (forMask) {
        return `-webkit-mask-box-image-source:url('${src}');` +
            `-webkit-mask-box-image-slice:${g.s.t} ${g.s.r} ${g.s.b} ${g.s.l} fill;` +
            `-webkit-mask-box-image-width:${g.bw.t}px ${g.bw.r}px ${g.bw.b}px ${g.bw.l}px;` +
            `-webkit-mask-box-image-repeat:${rep};`;
    }
    sliceDebugProbe(src, sl, sx, sy, boxW, boxH);
    return `border-style:solid;border-width:${g.bw.t}px ${g.bw.r}px ${g.bw.b}px ${g.bw.l}px;border-image:url('${src}') ${g.s.t} ${g.s.r} ${g.s.b} ${g.s.l} fill ${rep};box-sizing:border-box;`;
}

// ── 9-slice 단일 비트맵 합성 ────────────────────────────────────────────────
// border-image 는 스펙상 9조각을 각각 독립 사각형으로 그린다. 표시 배율이 소수(플레이뷰 fit 스케일,
// 게임 화면맞춤 스케일)면 조각 경계가 디바이스 픽셀 격자를 벗어나고, 인접 조각의 AA 가장자리
// 커버리지가 100% 로 합쳐지지 않아 그 틈으로 뒤 배경이 실금(눈금선)으로 비친다 — CSS 로는 이 조각
// 합성을 제어할 속성이 없다. 조각들을 캔버스에 미리 한 장으로 합성하면 단일 텍스처가 되어 어떤
// 배율에서도 내부 이음매가 생길 수 없다(유니티가 9-slice 를 단일 드로우콜 메시로 그리는 것과 동일 원리).
// 기하는 sliceGeometry 단일 소스를 그대로 써서 border-image 출력과 픽셀 동일. 초기 페인트는 기존
// border-image 로 먼저 그려지고(플래시 없음), 합성이 끝나면 background 로 교체된다.
// 에디터 에디트 뷰는 sliceBitmap:false 옵션으로 기존 경로 유지 — 실시간 리사이즈 중 합성 비용 0.
const _sliceImgCache = new Map();     // src → Promise<HTMLImageElement> (디코드 공유)
const _sliceBitmapCache = new Map();  // 합성키 → Promise<dataURL|null> (같은 이미지·slice·박스는 재합성 없음)
const SLICE_BITMAP_CACHE_MAX = 60;    // 세션 중 크기 변주 누적 대비 단순 캡 — 넘치면 통째로 비움
function _loadSliceImage(src) {
    if (!_sliceImgCache.has(src)) {
        _sliceImgCache.set(src, new Promise((resolve, reject) => {
            const im = new Image();
            // decode() — 픽셀 디코드를 오프스레드로 미리 끝내 drawImage 시점의 메인 스레드 동기 디코드 방지
            im.onload = () => { (im.decode ? im.decode().catch(() => {}) : Promise.resolve()).then(() => resolve(im)); };
            im.onerror = () => { _sliceImgCache.delete(src); reject(new Error('[SceneRenderer] slice 이미지 로드 실패: ' + src)); };
            im.src = src;
        }));
    }
    return _sliceImgCache.get(src);
}
function composeSliceBitmap(style, src, sx, sy, boxW, boxH) {
    const sl = style?.slice;
    if (!sl?.enabled || !src || !(boxW > 0 && boxH > 0) || typeof document === 'undefined') return Promise.resolve(null);
    const ps = Math.max(1, Math.min(3, Math.round((typeof window !== 'undefined' && window.devicePixelRatio) || 1)));
    const key = [src, sl.left, sl.top, sl.right, sl.bottom, sl.scale, sl.repeat, sx, sy, boxW, boxH, ps].join('|');
    if (_sliceBitmapCache.has(key)) return _sliceBitmapCache.get(key);
    if (_sliceBitmapCache.size >= SLICE_BITMAP_CACHE_MAX) _sliceBitmapCache.clear();
    const p = _loadSliceImage(src).then(im => {
        const natW = im.naturalWidth, natH = im.naturalHeight;
        if (!(natW > 0 && natH > 0)) return null;
        const g = sliceGeometry(sl, sx, sy, boxW, boxH, natW, natH);
        // 소스 slice 는 CSS 규칙대로 합이 원본을 넘으면 비례 축소(모서리 소스가 겹치지 않게)
        const S = { l: g.s.l, t: g.s.t, r: g.s.r, b: g.s.b };
        if (S.l + S.r > natW && S.l + S.r > 0) { const k = natW / (S.l + S.r); S.l *= k; S.r *= k; }
        if (S.t + S.b > natH && S.t + S.b > 0) { const k = natH / (S.t + S.b); S.t *= k; S.b *= k; }
        const bw = g.bw, cw = g.contentW, ch = g.contentH;
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(boxW * ps));
        canvas.height = Math.max(1, Math.round(boxH * ps));
        const ctx = canvas.getContext('2d');
        ctx.scale(ps, ps);
        ctx.imageSmoothingEnabled = true;
        if (ctx.imageSmoothingQuality) ctx.imageSmoothingQuality = 'high';
        const draw = (sx0, sy0, sw, sh, dx, dy, dw, dh) => {
            if (!(sw > 0 && sh > 0 && dw > 0 && dh > 0)) return;
            ctx.drawImage(im, sx0, sy0, sw, sh, dx, dy, dw, dh);
        };
        // 변/중앙 채움 — stretch=늘리기 1회, tile(round)=모서리와 같은 배율의 타일을 정수 개로 맞춰 반복
        const tiled = sl.repeat === 'tile';
        const kx = (sl.scale || 1) * sx * g.fx, ky = (sl.scale || 1) * sy * g.fy;
        const fill = (sx0, sy0, sw, sh, dx, dy, dw, dh, tileX, tileY) => {
            if (!(sw > 0 && sh > 0 && dw > 0 && dh > 0)) return;
            if (!tiled) { draw(sx0, sy0, sw, sh, dx, dy, dw, dh); return; }
            const nx = tileX ? Math.max(1, Math.round(dw / (sw * kx))) : 1;
            const ny = tileY ? Math.max(1, Math.round(dh / (sh * ky))) : 1;
            const tw = dw / nx, th = dh / ny;
            for (let i = 0; i < nx; i++) for (let j = 0; j < ny; j++) draw(sx0, sy0, sw, sh, dx + i * tw, dy + j * th, tw, th);
        };
        // 모서리 4 (항상 그림 — CSS 와 동일)
        draw(0, 0, S.l, S.t, 0, 0, bw.l, bw.t);
        draw(natW - S.r, 0, S.r, S.t, boxW - bw.r, 0, bw.r, bw.t);
        draw(0, natH - S.b, S.l, S.b, 0, boxH - bw.b, bw.l, bw.b);
        draw(natW - S.r, natH - S.b, S.r, S.b, boxW - bw.r, boxH - bw.b, bw.r, bw.b);
        // 변 4 + 중앙(fill) — CSS 스펙의 '비어짐'(slice 합 ≥ 원본) 규칙 준수
        const srcCW = natW - S.l - S.r, srcCH = natH - S.t - S.b;
        if (!g.emptyX) {
            fill(S.l, 0, srcCW, S.t, bw.l, 0, cw, bw.t, true, false);
            fill(S.l, natH - S.b, srcCW, S.b, bw.l, boxH - bw.b, cw, bw.b, true, false);
        }
        if (!g.emptyY) {
            fill(0, S.t, S.l, srcCH, 0, bw.t, bw.l, ch, false, true);
            fill(natW - S.r, S.t, S.r, srcCH, boxW - bw.r, bw.t, bw.r, ch, false, true);
        }
        if (!g.emptyX && !g.emptyY) fill(S.l, S.t, srcCW, srcCH, bw.l, bw.t, cw, ch, true, true);
        // 인코드는 toBlob(비동기·백그라운드) — toDataURL 은 동기 PNG 인코드라 큰 캔버스에서 메인 스레드를
        // 수십 ms 멈출 수 있다. blob URL 은 문서 수명 동안 유지되므로 revoke 하지 않는다(플레이뷰 iframe 은
        // 문서 파기와 함께 자동 해제, 게임은 씬당 조합 수가 적어 캡 초과 유출이 실질 무해).
        return new Promise(resolve => {
            if (canvas.toBlob) canvas.toBlob(b => resolve(b ? URL.createObjectURL(b) : canvas.toDataURL('image/png')), 'image/png');
            else resolve(canvas.toDataURL('image/png'));
        });
    }).catch(err => { console.warn('[SceneRenderer] 9-slice 비트맵 합성 실패 — border-image 유지:', err); return null; });
    _sliceBitmapCache.set(key, p);
    return p;
}
// 이미 border-image 로 그려진 slice 엘리먼트를 합성 완료 시점에 단일 비트맵 배경으로 교체.
// 합성 실패 시 아무것도 안 바꿔 기존 border-image 가 그대로 남는다(안전 폴백).
function applySliceBitmapUpgrade(el, style, src, sx, sy, boxW, boxH) {
    composeSliceBitmap(style, src, sx, sy, boxW, boxH).then(url => {
        if (!url) return;
        el.style.border = 'none';
        el.style.borderImage = 'none';
        el.style.background = `url('${url}') 0 0 / 100% 100% no-repeat`;
    });
}

// slice 붕괴(모서리만 남고 중앙이 사라짐) 사유 문자열 — 진단 로그와 편집기 경고 공용.
// 원인은 두 갈래: CSS 스펙의 '중앙·변 비어짐'(slice 합 ≥ 원본) / 박스가 모서리 합보다 작아 콘텐츠 박스가 0.
function sliceCollapseReasons(g) {
    const out = [];
    if (g.emptyX && g.emptyY) out.push('스펙: 양축 slice 합 ≥ 원본 → 모서리 4개만 남음(중앙·변 전부 비어짐)');
    else if (g.emptyX) out.push('스펙: L+R ≥ 원본W → 상/하변 + 중앙 비어짐');
    else if (g.emptyY) out.push('스펙: T+B ≥ 원본H → 좌/우변 + 중앙 비어짐');
    if (g.contentW <= 0) out.push('모서리가 박스보다 큼 → 중앙 폭 0');
    if (g.contentH <= 0) out.push('모서리가 박스보다 큼 → 중앙 높이 0');
    return out;
}

// 9-slice 진단 로그 — 증상 원인을 추정 대신 로그로 판정한다. 켜기: window.__sliceDebug = true
// 원본 크기는 <img> 비동기 probe 로 확인하므로 로그가 한 프레임 늦게 찍힌다. 같은 조건은 1회만 출력.
const _sliceDbgNat = new Map();      // src → {w,h} | null(로딩중)
const _sliceDbgSeen = new Set();     // 중복 출력 억제 키
function sliceDebugProbe(src, sl, sx, sy, boxW, boxH) {
    if (typeof window === 'undefined' || !window.__sliceDebug) return;
    const key = [src, sl.left, sl.top, sl.right, sl.bottom, sl.scale, sx, sy, boxW, boxH].join('|');
    if (_sliceDbgSeen.has(key)) return;
    _sliceDbgSeen.add(key);
    const nat = _sliceDbgNat.get(src);
    if (nat === undefined) {
        _sliceDbgNat.set(src, null);
        const probe = new Image();
        probe.onload = () => {
            _sliceDbgNat.set(src, { w: probe.naturalWidth, h: probe.naturalHeight });
            _sliceDbgSeen.delete(key);
            sliceDebugProbe(src, sl, sx, sy, boxW, boxH);
        };
        probe.onerror = () => { _sliceDbgNat.set(src, { w: 0, h: 0 }); };
        probe.src = src;
        return;
    }
    if (!nat) { _sliceDbgSeen.delete(key); return; }   // 아직 로딩중 — 다음 호출에서 다시 시도
    const g = sliceGeometry(sl, sx, sy, boxW, boxH, nat.w, nat.h);
    const causes = sliceCollapseReasons(g);
    const line = {
        src: String(src).split('/').pop(),
        원본: `${nat.w}x${nat.h}`,
        slice: `L${g.s.l} T${g.s.t} R${g.s.r} B${g.s.b}`,
        '합/원본': `${g.s.l + g.s.r}/${nat.w}, ${g.s.t + g.s.b}/${nat.h}`,
        박스: `${boxW}x${boxH}`,
        '렌더스케일': `${sx}x${sy}`,
        'sliceScale': sl.scale || 1,
        repeat: sl.repeat === 'tile' ? 'tile(round)' : 'stretch',
        '클램프fx/fy': `${Math.round(g.fx * 1000) / 1000}/${Math.round(g.fy * 1000) / 1000}`,
        borderWidth: `T${g.bw.t} R${g.bw.r} B${g.bw.b} L${g.bw.l}`,
        콘텐츠박스: `${g.contentW}x${g.contentH}`,
        권장sliceScale: nat.w > 0 && nat.h > 0 ? sliceFitScale(sl, sx, sy, boxW, boxH, nat.w, nat.h) : null,
        판정: causes.length ? causes.join(' / ') : '정상(중앙 그려짐)',
    };
    if (causes.length) console.warn('[slice][이상]', line);
    else console.log('[slice][정상]', line);
}

// 중앙이 붕괴하지 않는 sliceScale(모서리 표시 배율) 권장값 — 편집기의 '자동' 버튼과 진단 로그 공용.
// 기준은 박스/원본 비율(유니티 임포터가 축소 배치 시 sliceScale: s 를 쓰는 것과 같은 규칙) = 원본을 균일
// 축소한 모습이 된다. 그래도 중앙이 0 이면(원본 대비 slice 가 과도) 중앙 1px 이 남을 때까지 더 줄인다.
function sliceFitScale(sl, sx, sy, boxW, boxH, natW, natH) {
    const s = { t: Math.max(0, sl?.top || 0), r: Math.max(0, sl?.right || 0), b: Math.max(0, sl?.bottom || 0), l: Math.max(0, sl?.left || 0) };
    let fit = Math.min(1, natW > 0 ? boxW / (natW * sx) : 1, natH > 0 ? boxH / (natH * sy) : 1);
    const capX = (s.l + s.r) > 0 ? (boxW - 1) / ((s.l + s.r) * sx) : Infinity;
    const capY = (s.t + s.b) > 0 ? (boxH - 1) / ((s.t + s.b) * sy) : Infinity;
    fit = Math.min(fit, capX, capY);
    return Math.max(0.05, Math.floor(fit * 1000) / 1000);   // 내림 — 반올림으로 다시 박스를 넘는 것 방지
}

// contract 축약 공통 판정: 스타일이 전부 기본값(그림자 off·틴트 off·stretch off·slice off)이면 style 생략 가능
function isDefaultImageStyle(style) {
    return !!style && style.shadow?.enabled === false && (style.tint?.mode || 'off') === 'off' && !style.stretch && !style.slice?.enabled;
}

function findEffect(effects, type) {
    return (effects || []).find(e => e && e.type === type) || null;
}

function imageShadowCss(style) {
    const sh = style?.shadow || {};
    if (!sh.enabled) return '';
    return `drop-shadow(${sh.x || 0}px ${sh.y ?? 4}px ${sh.blur ?? 8}px ${hexToRgba(sh.color || '#000000', sh.opacity ?? 50)})`;
}

// 색 채우기(재색칠): 별도 레이어/마스크를 겹치면 안티앨리어싱 가장자리의 알파가 어긋나
// 틴트된 이미지끼리 겹칠 때 1px 경계선(seam)이 생긴다.
// → SVG 필터로 픽셀 자체를 재색칠한다. 알파(실루엣)는 손대지 않으므로 원본과 동일 → seam 없음.
//   tint(색조): feColorMatrix 로 명암(luminance)×색상 → 흰색은 색상, 검정은 검정(명암 유지).
//   overlay(덧입히기): feFlood 단색을 SourceAlpha 로 클리핑 → 불투명 페인트.
//   strength: feComposite arithmetic 으로 원본과 보간(알파 보존).
// image 레이어와 컴포넌트 내장 이미지(visual.images[])가 공유하는 단일 헬퍼.
function imageTintFilterCss(style) {
    const tint = style?.tint;
    const mode = tint?.mode || 'off';
    const s = (tint?.strength ?? 100) / 100;
    if (mode === 'off' || s <= 0) return '';
    let r = 255, g = 59, b = 48;
    const col = tint.color || '#ff3b30';
    const hx = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i.exec(col);
    if (hx) { r = parseInt(hx[1], 16); g = parseInt(hx[2], 16); b = parseInt(hx[3], 16); }
    else { const rm = /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i.exec(col); if (rm) { r = +rm[1]; g = +rm[2]; b = +rm[3]; } }
    const k2 = (1 - s).toFixed(4), k3 = s.toFixed(4);
    let body;
    if (mode === 'overlay') {
        body = `<feFlood flood-color="rgb(${r},${g},${b})" result="f"/>`
             + `<feComposite in="f" in2="SourceAlpha" operator="in" result="c"/>`
             + `<feComposite in="SourceGraphic" in2="c" operator="arithmetic" k1="0" k2="${k2}" k3="${k3}" k4="0"/>`;
    } else { // tint: luminance × color (명암 유지)
        const lum = c => `${(0.2126 * c).toFixed(5)} ${(0.7152 * c).toFixed(5)} ${(0.0722 * c).toFixed(5)} 0 0`;
        body = `<feColorMatrix type="matrix" values="${lum(r / 255)} ${lum(g / 255)} ${lum(b / 255)} 0 0 0 1 0" result="t"/>`
             + `<feComposite in="SourceGraphic" in2="t" operator="arithmetic" k1="0" k2="${k2}" k3="${k3}" k4="0"/>`;
    }
    // 모바일 WebKit 은 filter:url(data:...) 형태의 data-URI SVG 필터를 무시한다
    // (요소는 정상 표시되나 tint 가 적용 안 됨). → <filter> 를 문서에 인라인 등록하고 url(#id) 참조.
    if (typeof document === 'undefined') return '';
    const fkey = `${mode}|${r},${g},${b}|${k2}|${k3}`;
    let fid = TINT_FILTER_CACHE.get(fkey);
    if (!fid || !document.getElementById(fid)) {
        const NS = 'http://www.w3.org/2000/svg';
        let defs = document.getElementById('__tintFilterDefs');
        if (!defs) {
            defs = document.createElementNS(NS, 'svg');
            defs.id = '__tintFilterDefs';
            defs.setAttribute('width', '0');
            defs.setAttribute('height', '0');
            defs.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden;';
            (document.body || document.documentElement).appendChild(defs);
        }
        fid = '__tint' + (++_tintFilterSeq);
        const f = document.createElementNS(NS, 'filter');
        f.id = fid;
        f.setAttribute('color-interpolation-filters', 'sRGB');
        f.innerHTML = body;
        defs.appendChild(f);
        TINT_FILTER_CACHE.set(fkey, fid);
    }
    // base 태그(에디터 srcdoc 프리뷰)가 있으면 url(#id) 가 base 기준으로 해석돼 깨지므로
    // 현재 문서 URL 로 정규화한다. 일반 게임 문서(base 없음)는 단순 #id 로 참조.
    const ref = document.querySelector('base[href]')
        ? `${location.href.split('#')[0]}#${fid}`
        : `#${fid}`;
    return `url("${ref}")`;
}

function componentModelFromVisual(visual) {
    return visual?.model || normalizeComponentVisualModel(visual).visualModel;
}

function componentEffectsFromVisual(visual) {
    return visual?.effects || normalizeComponentVisualModel(visual).effects;
}

// ── Shine Sweep (광채 스윕) — 컴포넌트/이미지 공용 정규화. source.shine = 에디터 저장 필드 ──
function normalizeShineEffect(source, target = 'self') {
    const cfg = source.shine || {};
    return {
        type: 'shine',
        source: { provider: 'internal', name: 'shine-sweep' },
        enabled: !!cfg.enabled,
        target,
        trigger: 'mount',
        params: {
            angle: cfg.angle ?? -20,
            widthPct: cfg.width ?? 28,
            opacity: cfg.opacity ?? 65,
            softness: cfg.softness ?? 70,
            durationS: cfg.duration ?? 0.9,
            intervalS: cfg.interval ?? 2,
            direction: cfg.direction === 'left' ? 'left' : 'right',
            color: cfg.color || '#ffffff',
        },
    };
}

// shine 키프레임 1회 주입. pct = (duration / (duration+interval)) × 100 — 나머지 구간은 화면 밖 대기(휴식).
function ensureShineKeyframes(pct, dir) {
    if (typeof document === 'undefined') return null;
    const id = `ui-shine-${pct}_${dir}`;
    if (document.getElementById(id)) return id;
    const from = dir === 'left' ? '120%' : '-60%';
    const to = dir === 'left' ? '-60%' : '120%';
    const st = document.createElement('style');
    st.id = id;
    st.textContent = `@keyframes ${id}{0%{left:${from}}${pct}%{left:${to}}100%{left:${to}}}`;
    document.head.appendChild(st);
    return id;
}

// 광채 스윕 오버레이 적용. 클리핑은 opts 로 대상 실루엣을 받는다:
//   opts.borderRadius — 컴포넌트 일반 도형(el 과 동일 radius, overflow 클리핑)
//   opts.clipPath     — ribbon/notch 등 clip-path 도형
//   opts.maskSrc      — 이미지: 자기 알파 실루엣을 mask 로 재사용 (maskFit: 'contain'|'100% 100%')
//   opts.maskBoxCss   — 9-slice 이미지: imageSliceCssText(…, forMask=true) 산출 mask-box-image 프래그먼트
//   opts.maskBitmap   — 9-slice 합성 비트맵 Promise(composeSliceBitmap) — 해석되면 mask-box-image 를
//                       단일 비트맵 mask 로 교체(조각 이음매 실금 제거, base 렌더와 동일 원리)
function applyShineEffect(el, effect, opts = {}) {
    if (!el || !el.querySelector) return;
    const old = el.querySelector(':scope > .ui-shine-overlay');
    if (old) old.remove();
    if (!effect?.enabled) return;
    const p = effect.params || {};
    const angle = Math.max(-80, Math.min(80, Number(p.angle ?? -20)));
    const widthPct = Math.max(2, Math.min(100, Number(p.widthPct ?? 28)));
    const opacity = Math.max(0, Math.min(100, Number(p.opacity ?? 65)));
    const softness = Math.max(0, Math.min(100, Number(p.softness ?? 70)));
    const dur = Math.max(0.2, Math.min(10, Number(p.durationS ?? 0.9)));
    const rest = Math.max(0, Math.min(30, Number(p.intervalS ?? 2)));
    const dir = p.direction === 'left' ? 'left' : 'right';
    const total = dur + rest;
    const pct = Math.max(1, Math.min(100, Math.round((dur / total) * 100)));
    const kf = ensureShineKeyframes(pct, dir);
    if (!kf) return;
    const solid = (100 - softness) / 2;
    const c = p.color || '#ffffff';
    const grad = `linear-gradient(90deg, transparent 0%, ${hexToRgba(c, opacity)} ${(50 - solid).toFixed(1)}%, ${hexToRgba(c, opacity)} ${(50 + solid).toFixed(1)}%, transparent 100%)`;
    const overlay = document.createElement('div');
    overlay.className = 'ui-shine-overlay';
    overlay.style.cssText = [
        'position:absolute;inset:0;pointer-events:none;overflow:hidden;z-index:3;',
        opts.borderRadius ? `border-radius:${opts.borderRadius};` : '',
        opts.clipPath ? `clip-path:${opts.clipPath};` : '',
        opts.maskSrc ? `-webkit-mask-image:url('${opts.maskSrc}');mask-image:url('${opts.maskSrc}');-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;-webkit-mask-position:center;mask-position:center;-webkit-mask-size:${opts.maskFit || 'contain'};mask-size:${opts.maskFit || 'contain'};` : '',
        opts.maskBoxCss || '',
    ].join('');
    const bar = document.createElement('div');
    bar.style.cssText = `position:absolute;top:-60%;height:220%;width:${widthPct}%;left:-60%;background:${grad};transform:skewX(${angle}deg);animation:${kf} ${total}s linear infinite;`;
    overlay.appendChild(bar);
    el.appendChild(overlay);
    if (opts.maskBitmap) {
        opts.maskBitmap.then(url => {
            if (!url || !overlay.parentNode) return;
            overlay.style.webkitMaskBoxImage = 'none';
            overlay.style.webkitMaskImage = `url('${url}')`;
            overlay.style.webkitMaskSize = '100% 100%';
            overlay.style.maskImage = `url('${url}')`;
            overlay.style.maskSize = '100% 100%';
        });
    }
}

// ── 오브젝트 마스크 (maskParentId) — 부모 실루엣 클리핑 평면 ─────────────────────
// 계약 레이어의 시각적 bounds (x,y = 좌상단, scale 은 top-left 기준 크기 배율 — 에디터/런타임 공통 규약)
function contractLayerBounds(l) {
    const sc = l.scale || 1, sx = (l.scaleX ?? 1) * sc, sy = (l.scaleY ?? 1) * sc;
    let w = l.visual?.width || 0, h = l.visual?.height || 0;
    const shape = l.visual?.model?.shape;
    if (shape) {
        const circle = shape.type === 'circle' || shape.type === 'ring';
        w = circle ? Math.max(shape.width || 60, shape.height || 60) : (shape.width || 100);
        h = circle ? Math.max(shape.width || 60, shape.height || 60) : (shape.height || 40);
    }
    return { x: l.x || 0, y: l.y || 0, w: w * sx, h: h * sy };
}

// ── 캐릭터 소켓(장착 지점) 변환 — 캐릭터 메이커 파츠 배치 수학의 단일 소스 ──────────────
// 에디터(조립 화면)와 런타임(게임)이 같은 결과를 내야 하므로 여기 한 곳에만 둔다.
//   layer   — x/y/rotation/scale 를 가진 레이어(에디터 레이어 · 계약 레이어 공용 — 필드명이 같다)
//   socket  — { x, y, rotation, scale }
//   bounds  — 배율이 포함된 {w,h} (에디터=getLayerBounds, 런타임=contractLayerBounds)
//   invert  — false: 로컬(소켓 원점 기준) → 절대 / true: 절대 → 로컬
// 회전·배율은 소켓 원점을 중심으로 걸린다. 레이어 중심 기준으로 계산하는 이유: CSS transform 의
// 기본 원점이 박스 중심이라 scale 이 바뀌어도 중심은 그대로이기 때문(에디터 free-item 과 동일 규약).
function applySocketTransform(layer, socket, bounds, invert) {
    if (!socket) return layer;
    const sc = socket.scale || 1;
    const lsc = layer.scale || 1;
    const sx = ((layer.scaleX ?? 1) * lsc) || 1;
    const sy = ((layer.scaleY ?? 1) * lsc) || 1;
    // 미스케일(고유) 박스 — scale 을 바꿔도 불변이므로 변환 전 값을 그대로 쓴다.
    const uw = (bounds.w || 0) / sx, uh = (bounds.h || 0) / sy;
    const cx = (layer.x || 0) + uw / 2, cy = (layer.y || 0) + uh / 2;
    const rot = (deg, x, y) => {
        const r = (deg || 0) * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
        return { x: x * c - y * s, y: x * s + y * c };
    };
    let nc;
    if (!invert) {
        const p = rot(socket.rotation || 0, cx * sc, cy * sc);
        nc = { x: (socket.x || 0) + p.x, y: (socket.y || 0) + p.y };
        layer.scale = lsc * sc;
        layer.rotation = (layer.rotation || 0) + (socket.rotation || 0);
    } else {
        const p = rot(-(socket.rotation || 0), cx - (socket.x || 0), cy - (socket.y || 0));
        nc = { x: p.x / sc, y: p.y / sc };
        layer.scale = lsc / sc;
        layer.rotation = (layer.rotation || 0) - (socket.rotation || 0);
    }
    layer.x = nc.x - uw / 2;
    layer.y = nc.y - uh / 2;
    return layer;
}

// ── 캐릭터 프레임 클립(스톱모션) 샘플링 — 에디터 미리보기와 런타임 재생의 단일 소스 ──────
// clip = { name, loop, frames: [{ tMs, pose: { 포즈키: {x,y,rotation,scale,scaleX,scaleY} } }] }
// 프레임은 "그 시각의 캔버스 전체 스냅샷"(몸통 + 장착 파츠). 프레임 사이는 선형 보간하므로
// 촘촘히 찍으면 스톱모션, 드물게 찍으면 부드러운 동작이 된다.
// 포즈 키 — 몸통 base:<stableId> / 파츠 slot:<socketId>:<파츠 내 순번>
// (파츠를 슬롯 기준으로 잡기 때문에 칼로 만든 궤적을 도끼로 갈아끼워도 그대로 이어받는다.)
function characterClipDuration(clip) {
    return (clip.frames || []).reduce((m, f) => Math.max(m, f.tMs || 0), 0);
}
function sampleCharacterClip(clip, tMs) {
    const frames = (clip.frames || []).slice().sort((a, b) => (a.tMs || 0) - (b.tMs || 0));
    if (!frames.length) return {};
    let prev = frames[0], next = frames[frames.length - 1];
    if (tMs <= (frames[0].tMs || 0)) { prev = next = frames[0]; }
    else if (tMs >= (frames[frames.length - 1].tMs || 0)) { prev = next = frames[frames.length - 1]; }
    else {
        for (let i = 0; i < frames.length - 1; i++) {
            if (tMs >= (frames[i].tMs || 0) && tMs <= (frames[i + 1].tMs || 0)) { prev = frames[i]; next = frames[i + 1]; break; }
        }
    }
    const span = (next.tMs || 0) - (prev.tMs || 0);
    const k = span > 0 ? (tMs - (prev.tMs || 0)) / span : 0;
    const mix = (a, b, d) => {
        const av = (a === undefined || a === null) ? d : a;
        const bv = (b === undefined || b === null) ? d : b;
        return av + (bv - av) * k;
    };
    const out = {};
    const keys = new Set(Object.keys(prev.pose || {}).concat(Object.keys(next.pose || {})));
    keys.forEach(key => {
        const p = (prev.pose || {})[key];
        const n = (next.pose || {})[key];
        const from = p || n, to = n || p;
        if (!from) return;
        out[key] = {
            x: mix(from.x, to.x, 0),
            y: mix(from.y, to.y, 0),
            rotation: mix(from.rotation, to.rotation, 0),
            scale: mix(from.scale, to.scale, 1),
            scaleX: mix(from.scaleX, to.scaleX, 1),
            scaleY: mix(from.scaleY, to.scaleY, 1),
            hidden: !!from.hidden,   // 표시 여부는 보간 불가 — 이전 프레임 값 유지(스텝)
        };
    });
    return out;
}

// 포즈(절대 트랜스폼)를 "휴지 자세 대비 델타" CSS transform 으로 바꾼다.
// 레이어 엘리먼트는 휴지 자세(authored)로 이미 배치돼 있으므로, 그것을 감싼 컨테이너에
// 델타만 걸면 결과가 곧 절대 포즈다. 원점은 레이어 중심 — 회전·배율이 제자리에서 걸린다.
// (도끼처럼 휴지 위치가 다른 파츠도 같은 계산으로 정확히 목표 포즈에 놓인다.)
function characterPoseCss(rest, pose, bounds, isDelta) {
    if (!pose) return '';
    let dx, dy, dr, kx, ky;
    if (isDelta) {
        // v3: 포즈 = 기본 자세 대비 델타(x/y/rotation 가산, scale 곱) — 파츠별 기본 크기·위치를
        // 유지한 채 모션만 공유한다(무기 교체 시 크기가 강제로 통일되던 v2 절대좌표 문제의 해법).
        dx = pose.x || 0;
        dy = pose.y || 0;
        dr = pose.rotation || 0;
        kx = ((pose.scaleX ?? 1) * (pose.scale ?? 1)) || 1;
        ky = ((pose.scaleY ?? 1) * (pose.scale ?? 1)) || 1;
    } else {
        // v2(구 발행본): 포즈 = 절대 좌표 — 현재 rest 와의 차로 델타를 만들어 절대 포즈에 착지시킨다.
        const rsc = rest.scale || 1;
        const rsx = ((rest.scaleX ?? 1) * rsc) || 1;
        const rsy = ((rest.scaleY ?? 1) * rsc) || 1;
        const psc = pose.scale ?? rsc;
        const psx = ((pose.scaleX ?? rest.scaleX ?? 1) * psc) || 1;
        const psy = ((pose.scaleY ?? rest.scaleY ?? 1) * psc) || 1;
        dx = (pose.x ?? rest.x ?? 0) - (rest.x || 0);
        dy = (pose.y ?? rest.y ?? 0) - (rest.y || 0);
        dr = (pose.rotation ?? rest.rotation ?? 0) - (rest.rotation || 0);
        kx = psx / rsx; ky = psy / rsy;
    }
    // scale 델타는 컨테이너 원점(시각적 중심) 기준으로 걸리지만, 좌표 규약은 배율 좌상단 기준(x,y 고정).
    // 중심 기준으로 커지며 좌상단이 밀린 만큼을 이동으로 보정한다(bounds = 휴지 자세 배율 포함 크기).
    const cx = bounds ? (kx - 1) * bounds.w / 2 : 0;
    const cy = bounds ? (ky - 1) * bounds.h / 2 : 0;
    return `translate(${dx + cx}px,${dy + cy}px) rotate(${dr}deg) scale(${kx},${ky})`;
}
// 포즈 컨테이너의 transform-origin — 레이어의 "시각적" 중심(캔버스 좌표). bounds 는 배율 포함.
// 배율은 좌상단 기준으로 걸리므로(런타임 scaleWrap transform-origin:0 0 · 에디터 .free-item top left)
// 시각적 박스는 x .. x+bounds.w — 중심은 bounds 를 그대로 반으로 가른다.
// (과거 bounds 를 배율로 나눠 원점이 미스케일 중심으로 밀렸고, scale≠1 파츠의 클립 회전이
//  어긋난 원점에서 돌아 "검이 날아가는" 증상의 원인이었다 — 게임 실측으로 판정됨)
function characterPoseOrigin(rest, bounds) {
    return `${(rest.x || 0) + bounds.w / 2}px ${(rest.y || 0) + bounds.h / 2}px`;
}

// 투사체 조준선을 화면 좌표로 — 발사 지점(촉)과 발사각을 반환한다. { x, y, angleDeg } (client 좌표) | null.
// 각도·좌표를 숫자로 합성하지 않고 브라우저가 이미 합성해둔 결과를 읽는다: 캐릭터 루트의 좌우반전
// (scaleX(-1))·포즈 회전·파츠 배율이 몇 겹이든 두 점의 실제 화면 위치에 전부 반영돼 있기 때문.
// visibility:hidden 은 레이아웃을 유지하므로 "사라지는 순간"(발사)에도 그대로 측정된다.
function characterAimWorld(poseEl) {
    const tail = poseEl && poseEl.querySelector('.sr-aim-tail');
    const tip = poseEl && poseEl.querySelector('.sr-aim-tip');
    if (!tail || !tip) return null;
    const a = tail.getBoundingClientRect(), b = tip.getBoundingClientRect();
    return { x: b.left, y: b.top, angleDeg: Math.atan2(b.top - a.top, b.left - a.left) * 180 / Math.PI };
}

// ── 위젯(표시/토글/슬라이더) contract 방출 판정 — key+필수 슬롯 완비 시 위젯 객체, 아니면 null ──
// 방출 지점이 두 곳(layerToContractLayer / 에디터 _mapGroups)이라 판정을 여기 한 곳에 둔다.
// visibility=슬롯 없음(호스트 자신), toggle=on·off 필수, slider=track·handle 필수(fill 옵션),
// fill=fill 필수(bg 옵션 — 배경 페어링 표시용, 런타임 동작 없음).
function widgetContractValue(wg) {
    if (!wg || !wg.key || !wg.type) return null;
    if (wg.type === 'visibility') return wg;
    if (wg.type === 'toggle') return (wg.on && wg.off) ? wg : null;
    if (wg.type === 'slider') return (wg.track && wg.handle) ? wg : null;
    if (wg.type === 'fill') return wg.fill ? wg : null;
    return null;
}

// 부모 실루엣대로 자식을 잘라내는 클리핑 평면(inset:0) 생성.
//   parent       — 계약 레이어 (component/image)
//   resolveAsset — 이미지 경로 해석 함수 (이미 해석된 경로면 항등)
//   boundsOv     — bounds 재계산 없이 외부가 주는 값 사용
//   opts.local   — 부모 몸체(inner) 안에 삽입되는 로컬 모드. bounds 는 {x:0,y:0,w,h}(몸체 박스)를 주고,
//                  회전은 몸체 바깥 rotWrap 이 이미 담당하므로 여기서 걸지 않는다.
// 컴포넌트=도형 clip-path, 이미지=자기 알파 mask-image(contain 은 원본비 해석 후 보정), 9-slice=박스 사각형.
function buildMaskClipPlane(parent, resolveAsset, boundsOv, opts = {}) {
    const b = boundsOv || contractLayerBounds(parent);
    if (!(b.w > 0 && b.h > 0)) return null;
    const el = document.createElement('div');
    let css = 'position:absolute;inset:0;';
    // 로컬 모드에선 회전을 걸면 rotWrap 회전과 이중 적용된다
    if (parent.rotation && !opts.local) css += `transform:rotate(${parent.rotation}deg);transform-origin:${b.x + b.w / 2}px ${b.y + b.h / 2}px;`;
    const shape = parent.visual?.model?.shape;
    if (shape) {
        const t = shape.type || 'rectangle';
        if (t === 'circle' || t === 'ring') {
            css += `clip-path:circle(${Math.max(b.w, b.h) / 2}px at ${b.x + b.w / 2}px ${b.y + b.h / 2}px);`;
        } else if (t === 'ribbon' || t === 'ribbon-left' || t === 'notch' || t === 'notch-left') {
            // _applyComponentVisual 의 clipPoly 와 동일 꼭짓점 — bounds 스케일에 맞춰 notch 도 비례
            const n = (shape.notch ?? 20) * (b.w / (shape.width || 100));
            const pts = t === 'ribbon'      ? [[0, 0], [b.w - n, 0], [b.w, b.h / 2], [b.w - n, b.h], [0, b.h]]
                : t === 'ribbon-left' ? [[n, 0], [b.w, 0], [b.w, b.h], [n, b.h], [0, b.h / 2]]
                : t === 'notch-left'  ? [[0, 0], [b.w, 0], [b.w, b.h], [0, b.h], [n, b.h / 2]]
                :                       [[0, 0], [b.w, 0], [b.w - n, b.h / 2], [b.w, b.h], [0, b.h]];
            css += `clip-path:polygon(${pts.map(([px, py]) => `${Math.round(b.x + px)}px ${Math.round(b.y + py)}px`).join(',')});`;
        } else {
            let r = shape.radius || 0;
            if (t === 'pill') r = b.h / 2;
            const round = t === 'top-round-rect' ? `${r}px ${r}px 0 0` : `${r}px`;
            css += `clip-path:inset(${b.y}px calc(100% - ${b.x + b.w}px) calc(100% - ${b.y + b.h}px) ${b.x}px round ${round});`;
        }
    } else {
        const resolve = resolveAsset || ((p) => p);
        const src = resolve(parent.image?.exportPath || parent.visual?.exportPath || '');
        const style = parent.image?.style || parent.visual?.style;
        if (src && !style?.slice?.enabled) {
            css += `-webkit-mask-image:url('${src}');mask-image:url('${src}');-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;`
                + `-webkit-mask-position:${b.x}px ${b.y}px;mask-position:${b.x}px ${b.y}px;-webkit-mask-size:${b.w}px ${b.h}px;mask-size:${b.w}px ${b.h}px;`;
            if (!style?.stretch) {
                // contain 렌더(레터박스)와 mask 정렬을 일치 — 원본비 해석 후 mask rect 를 실제 그려진 영역으로 보정
                const probe = new Image();
                probe.onload = () => {
                    if (!probe.naturalWidth || !probe.naturalHeight || !el.isConnected) return;
                    const f = Math.min(b.w / probe.naturalWidth, b.h / probe.naturalHeight);
                    const mw = probe.naturalWidth * f, mh = probe.naturalHeight * f;
                    const mx = b.x + (b.w - mw) / 2, my = b.y + (b.h - mh) / 2;
                    el.style.webkitMaskPosition = el.style.maskPosition = `${mx}px ${my}px`;
                    el.style.webkitMaskSize = el.style.maskSize = `${mw}px ${mh}px`;
                };
                probe.src = src;
            }
        } else {
            // 경로 미해석/9-slice — 박스 사각형으로 클리핑 (border-image 는 박스를 채우는 불투명 케이스가 일반적)
            css += `clip-path:inset(${b.y}px calc(100% - ${b.x + b.w}px) calc(100% - ${b.y + b.h}px) ${b.x}px);`;
        }
    }
    el.style.cssText = css;
    return el;
}

// ── Mask Flow — 마스크 자식이 부모 실루엣 안에서 흘러가는 이펙트 ─────────────────
// tiled=true: 자식 이미지를 타일 패턴으로 무한 스크롤(배경 infinite flow 와 동일 메커니즘).
// tiled=false: 자식 오브젝트 1개가 부모를 가로질러 통과 — 1회(once) 또는 loop+interval(shine sweep 규약).
function normalizeMaskFlowCfg(f) {
    // Tile(무한 패턴 채움)과 Flow(흘러가기 모션)는 독립 — 둘 중 하나라도 켜지면 설정 반환 (배경 tile + Infinite Scroll 과 동일 구조)
    if (!f || (!f.enabled && !f.tiled)) return null;
    return {
        enabled: !!f.enabled,
        direction: BG_SCROLL_DIRS[f.direction] ? f.direction : 'right',
        tiled: !!f.tiled,
        tileMode: f.tileMode === 'brick' ? 'brick' : 'tile',
        tileSize: Math.max(2, Math.round(Number(f.tileSize) || 64)),
        tileSpeed: Math.max(0.5, Math.min(60, Number(f.tileSpeed) || 4)),
        tilePad: Math.max(0, Math.min(300, Number(f.tilePad) || 0)),
        duration: Math.max(0.2, Math.min(60, Number(f.duration) || 4)),
        loop: f.loop !== false,
        interval: Math.max(0, Math.min(30, Number(f.interval) || 0)),
    };
}

// 통과 이동 키프레임 1회 주입 — (시작/끝 translate px, 진행 pct) 조합별 dedup
function ensureMaskFlowKeyframes(sx, sy, ex, ey, pct) {
    if (typeof document === 'undefined') return null;
    const id = 'ui-mask-flow-' + [sx, sy, ex, ey, pct].map(n => String(n).replace('-', 'm')).join('_');
    if (document.getElementById(id)) return id;
    const st = document.createElement('style');
    st.id = id;
    st.textContent = `@keyframes ${id}{0%{transform:translate(${sx}px,${sy}px)}${pct}%{transform:translate(${ex}px,${ey}px)}100%{transform:translate(${ex}px,${ey}px)}}`;
    document.head.appendChild(st);
    return id;
}

// 비타일 통과 이동 — wrapEl 의 콘텐츠를 flow div 로 감싸 translate 애니메이션 (wrapEl 자체 transform 보존).
// pb/cb = 부모/자식 bounds(절대좌표), opts.invScaleX/Y = 에디터 wrapper CSS scale 상쇄 계수(런타임=1)
function applyMaskFlow(wrapEl, flow, pb, cb, opts = {}) {
    if (!wrapEl || !flow || flow.tiled) return;
    const dir = BG_SCROLL_DIRS[flow.direction];
    if (!dir) return;
    const [ux, uy] = dir;
    if (!ux && !uy) return;
    const isx = opts.invScaleX || 1, isy = opts.invScaleY || 1;
    // 진입 가장자리 바깥 → 반대편 가장자리 바깥 (부모 실루엣을 완전히 통과)
    const sx = ux === 0 ? 0 : (ux > 0 ? (pb.x - cb.w) - cb.x : (pb.x + pb.w) - cb.x);
    const ex = ux === 0 ? 0 : (ux > 0 ? (pb.x + pb.w) - cb.x : (pb.x - cb.w) - cb.x);
    const sy = uy === 0 ? 0 : (uy > 0 ? (pb.y - cb.h) - cb.y : (pb.y + pb.h) - cb.y);
    const ey = uy === 0 ? 0 : (uy > 0 ? (pb.y + pb.h) - cb.y : (pb.y - cb.h) - cb.y);
    const total = flow.loop ? flow.duration + flow.interval : flow.duration;
    const pct = flow.loop ? Math.max(1, Math.min(100, Math.round(flow.duration / total * 100))) : 100;
    const id = ensureMaskFlowKeyframes(Math.round(sx * isx), Math.round(sy * isy), Math.round(ex * isx), Math.round(ey * isy), pct);
    if (!id) return;
    const flowDiv = document.createElement('div');
    flowDiv.className = 'ui-mask-flow';
    flowDiv.style.cssText = `animation:${id} ${total}s linear ${flow.loop ? 'infinite' : '1 forwards'};`;
    while (wrapEl.firstChild) flowDiv.appendChild(wrapEl.firstChild);
    wrapEl.appendChild(flowDiv);
}

// 마스크 자식 Tile/Brick 무한 패턴 — 부모 bounds 크기 div 를 만들고 공용 applyPatternFill 에 위임(배경과 단일 소스).
// tileSize = 배경 Tile Size / Brick Height 와 동일 규약(tile=정사각 셀, brick=벽돌 높이·폭은 이미지 비율). tilePad = tile 여백.
// 스크롤 모션은 flow.enabled(Flow 흘러가기) 일 때만 — 끄면 정적 무한 패턴 채움. 호출자는 원본 자식을 숨긴다. (cb 는 시그니처 유지용)
function buildMaskFlowTileEl(src, pb, cb, flow) {
    if (!src) return null;
    const brick = flow.tileMode === 'brick';
    const size = Math.max(2, Math.round(flow.tileSize || 64));
    const div = document.createElement('div');
    div.className = 'ui-mask-flow-tile';
    div.style.cssText = `position:absolute;left:${pb.x}px;top:${pb.y}px;width:${pb.w}px;height:${pb.h}px;pointer-events:none;`;
    applyPatternFill(div, {
        imageUrl: src,
        mode: brick ? 'brick' : 'tile',
        cellW: size, cellH: size,
        pad: brick ? 0 : (flow.tilePad || 0),
        scroll: flow.enabled ? { enabled: true, direction: flow.direction, secPerTile: flow.tileSpeed } : null,
        stamp: `mask|${brick ? 'brick' : 'tile'}|${src}|${size}|${flow.tilePad || 0}`,
    });
    return div;
}

function modelShadow(model, type) {
    return (model?.shadows || []).find(s => s.type === type) || {};
}

function componentShadowCss(model, isClipped) {
    const shadows = [];
    const filterEffects = [];
    // outline 링(spread 전용 box-shadow) — clip-path 도형은 drop-shadow 로 링을 만들 수 없어 미지원
    const outlineW = model?.border?.outlineWidth || 0;
    if (outlineW > 0 && !isClipped) {
        shadows.push(`0 0 0 ${outlineW}px ${model.border.outlineColor || '#1e4a80'}`);
    }
    const depth = modelShadow(model, 'depth-edge');
    if (depth.enabled && depth.size > 0) {
        if (isClipped) filterEffects.push(`drop-shadow(0px ${depth.size}px 0px ${depth.color || '#000'})`);
        else shadows.push(`0 ${depth.size}px 0 0 ${depth.color || '#000'}`);
    }
    const outer = modelShadow(model, 'outer');
    if (outer.enabled) {
        const css = `${outer.x || 0}px ${outer.y ?? 4}px ${outer.blur ?? 8}px ${hexToRgba(outer.color || '#000000', outer.opacity ?? 30)}`;
        if (isClipped) filterEffects.push(`drop-shadow(${css})`);
        else shadows.push(css);
    }
    const gloss = modelShadow(model, 'gloss');
    if (gloss.enabled) {
        const gb = gloss.blur ?? 8;
        shadows.push(`inset 0 ${gloss.size ?? 10}px ${gb}px ${-Math.round(gb / 2)}px ${hexToRgba(gloss.color || '#ffffff', gloss.opacity ?? 45)}`);
    }
    const inner = modelShadow(model, 'inner');
    if (inner.enabled) {
        const blur = inner.blur ?? 4;
        shadows.push(`inset ${inner.x || 0}px ${inner.y ?? 2}px ${blur * 2}px ${-blur}px ${hexToRgba(inner.color || '#ffffff', inner.opacity ?? 20)}`);
    }
    return { shadows, filterEffects };
}

// 3D edge(depth)가 없는 컴포넌트/이미지는 translateY 가 0 이라 눌림감이 거의 없으므로
// depth 가 없을 때 적용할 기본 눌림 깊이(px). depthSize 기본값(3)과 동일하게 맞춤.
const PRESS_FALLBACK_DEPTH_PX = 3;

function pressedComponentShadowCss(model) {
    const pressed = [];
    // outline 링은 눌림 중에도 유지 (버튼 외곽선이 사라지면 부자연스러움)
    const outlineW = model?.border?.outlineWidth || 0;
    if (outlineW > 0) {
        pressed.push(`0 0 0 ${outlineW}px ${model.border.outlineColor || '#1e4a80'}`);
    }
    const outer = modelShadow(model, 'outer');
    if (outer.enabled) {
        pressed.push(`${outer.x || 0}px ${Math.round((outer.y ?? 4) * 0.3)}px ${Math.round((outer.blur ?? 8) * 0.5)}px ${hexToRgba(outer.color || '#000000', outer.opacity ?? 30)}`);
    }
    // gloss 는 눌림 시 축소 — 가라앉으며 조명 반사가 줄어드는 표현
    const gloss = modelShadow(model, 'gloss');
    if (gloss.enabled) {
        const gb = Math.max(1, Math.round((gloss.blur ?? 8) * 0.6));
        pressed.push(`inset 0 ${Math.round((gloss.size ?? 10) * 0.4)}px ${gb}px ${-Math.round(gb / 2)}px ${hexToRgba(gloss.color || '#ffffff', Math.round((gloss.opacity ?? 45) * 0.55))}`);
    }
    const inner = modelShadow(model, 'inner');
    if (inner.enabled) {
        const blur = inner.blur ?? 4;
        pressed.push(`inset ${inner.x || 0}px ${inner.y ?? 2}px ${blur * 2}px ${-blur}px ${hexToRgba(inner.color || '#ffffff', inner.opacity ?? 20)}`);
    }
    return pressed.length ? pressed.join(',') : 'none';
}

function applyPressEffect(el, effect, opts = {}) {
    if (el._uiPressHandlers && el.removeEventListener) {
        const h = el._uiPressHandlers;
        el.removeEventListener('mousedown', h.down); el.removeEventListener('mouseup', h.up); el.removeEventListener('mouseleave', h.up);
        el.removeEventListener('touchstart', h.down); el.removeEventListener('touchend', h.up);
        el._uiPressHandlers = null;
    }
    if (!effect?.enabled) {
        el.style.cursor = '';
        el.style.transition = '';
        return;
    }
    const params = effect.params || {};
    const dur = params.transitionMs || 100;
    const scale = (params.scale ?? 95) / 100;
    const bright = (params.brightness ?? 100) / 100;
    const depthPx = opts.depthPx || PRESS_FALLBACK_DEPTH_PX;
    const normalShadow = opts.normalShadow ?? el.style.boxShadow;
    const pressedShadow = opts.pressedShadow;
    const baseFilter = opts.baseFilter || '';
    // bevel 면 가라앉기: 눌림 시 아래 베벨이 얇아지며 평탄면이 내려앉는다. opts.bevelPress = {top, bottom}(평시 인셋 px)
    const bevelPress = opts.bevelPress || null;
    const bevelFace = () => (el.querySelector ? el.querySelector(':scope > .bevel-face-layer') : null);
    el.style.cursor = 'pointer';
    el.style.transition = pressedShadow
        ? `transform ${dur}ms ease,filter ${dur}ms ease,box-shadow ${dur}ms ease`
        : `transform ${dur}ms ease,filter ${dur}ms ease`;
    const down = () => {
        el.style.transform = `${depthPx ? `translateY(${depthPx}px) ` : ''}scale(${scale})`;
        el.style.filter = baseFilter ? `${baseFilter} brightness(${bright})` : `brightness(${bright})`;
        if (pressedShadow) el.style.boxShadow = pressedShadow;
        if (bevelPress) {
            const f = bevelFace();
            if (f) {
                f.style.transition = `top ${dur}ms ease,bottom ${dur}ms ease`;
                f.style.top = `${Math.max(1, bevelPress.top - 2)}px`;
                f.style.bottom = `${Math.max(bevelPress.top, bevelPress.bottom - depthPx)}px`;
            }
        }
    };
    const up = () => {
        el.style.transform = '';
        el.style.filter = baseFilter;
        if (pressedShadow) el.style.boxShadow = normalShadow;
        if (bevelPress) {
            const f = bevelFace();
            if (f) {
                f.style.top = `${bevelPress.top}px`;
                f.style.bottom = `${bevelPress.bottom}px`;
            }
        }
    };
    el.addEventListener('mousedown', down); el.addEventListener('mouseup', up); el.addEventListener('mouseleave', up);
    el.addEventListener('touchstart', down, { passive: true }); el.addEventListener('touchend', up);
    el._uiPressHandlers = { down, up };
}

function ensureCssEffectProvider(provider) {
    if (typeof document === 'undefined') return Promise.resolve(false);
    const entry = CSS_EFFECT_PROVIDER_STYLES[provider];
    if (!entry) return Promise.resolve(false);
    const id = 'ui-css-effect-provider-' + provider.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
    const existing = document.getElementById(id);
    // 과거 주입분(프라미스 미추적)은 로드 완료로 간주 — 신규 주입만 _loadPromise 로 추적
    if (existing) return existing._loadPromise || Promise.resolve(true);
    const link = document.createElement('link');
    link.id = id;
    link.rel = 'stylesheet';
    console.info('[SceneRenderer] css effect provider inject', { provider, href: vendorUrl(entry.local), t: performance.now().toFixed(1) });
    const p = loadStylesheetWithFallback(link, vendorUrl(entry.local), entry.cdn);
    p.then(ok => console.info('[SceneRenderer] css effect provider loaded', { provider, ok, t: performance.now().toFixed(1) }));
    document.head.appendChild(link);
    return p;
}

// animate.css 에 없는 자체 CSS 애니메이션 클래스 — 1회 주입(기존 ensure*Keyframes 들과 같은 패턴).
// ui-blink-once: animate.css 의 flash 는 키프레임이 0/50/100% 불투명 · 25/75% 투명이라
// 한 사이클에 2번 깜빡인다. 1회 점멸은 가운데서 한 번만 꺼지는 별도 키프레임이 필요하다.
// 지속시간/fill-mode 는 animate__animated(baseClass)가 --animate-duration 으로 그대로 처리한다.
function ensureLocalCssAnimationKeyframes() {
    if (typeof document === 'undefined') return;
    ensureSpinKeyframes();   // spin-360 프리셋이 ui-spin/ui-spin-rev 키프레임을 공유한다
    if (document.getElementById('ui-css-animation-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-css-animation-keyframes';
    st.textContent =
        '@keyframes ui-blink-once{0%,100%{opacity:1}50%{opacity:0}}' +
        '.ui-blink-once{animation-name:ui-blink-once}' +
        // ui-charge-pop: 살짝 수축한 채 부들부들 떨다가 빵 터지며 감쇠 바운스로 복귀
        '@keyframes ui-charge-pop{' +
        '0%{transform:scale(1)}' +
        '8%{transform:scale(.86) rotate(-2deg)}14%{transform:scale(.85) rotate(2deg)}' +
        '20%{transform:scale(.84) rotate(-2.5deg)}26%{transform:scale(.85) rotate(2.5deg)}' +
        '32%{transform:scale(.83) rotate(-3deg)}38%{transform:scale(.84) rotate(3deg)}' +
        '44%{transform:scale(.82) rotate(-3deg)}50%{transform:scale(.8)}' +
        '60%{transform:scale(1.32)}72%{transform:scale(.93)}82%{transform:scale(1.1)}' +
        '90%{transform:scale(.97)}100%{transform:scale(1)}' +
        '}' +
        '.ui-charge-pop{animation-name:ui-charge-pop}' +
        // ui-squash-jump: 바닥 기준(origin 50% 100%) — 상단이 아래로 눌리며 떨다가 점프 후 착지 바운스
        '@keyframes ui-squash-jump{' +
        '0%{transform:translateY(0) scale(1,1)}' +
        '8%{transform:translateY(0) scale(1.08,.78) rotate(-1.5deg)}' +
        '14%{transform:translateY(0) scale(1.07,.76) rotate(1.5deg)}' +
        '20%{transform:translateY(0) scale(1.09,.75) rotate(-2deg)}' +
        '26%{transform:translateY(0) scale(1.07,.74) rotate(2deg)}' +
        '32%{transform:translateY(0) scale(1.1,.73) rotate(-2deg)}' +
        '38%{transform:translateY(0) scale(1.08,.72)}' +
        '48%{transform:translateY(-46%) scale(.92,1.18)}' +
        '56%{transform:translateY(-58%) scale(.96,1.06)}' +
        '68%{transform:translateY(0) scale(1.12,.82)}' +
        '78%{transform:translateY(-14%) scale(.98,1.04)}' +
        '86%{transform:translateY(0) scale(1.05,.92)}' +
        '93%{transform:translateY(-4%) scale(1,1.01)}' +
        '100%{transform:translateY(0) scale(1,1)}' +
        '}' +
        '.ui-squash-jump{animation-name:ui-squash-jump;transform-origin:50% 100%}' +
        // ui-squash-crouch / ui-squash-launch — squash-jump 를 둘로 쪼갠 것(0~38% / 38~100% 재매핑).
        // crouch 는 눌린 자세(scale 1.08,.72)로 "끝나고"(fill both 로 유지), launch 는 그 자세에서 시작 —
        // 사이에 image-swap 을 끼우면 교체된 이미지로 점프 착지가 이어진다(개봉 연출 2단 구성).
        '@keyframes ui-squash-crouch{' +
        '0%{transform:translateY(0) scale(1,1)}' +
        '21%{transform:translateY(0) scale(1.08,.78) rotate(-1.5deg)}' +
        '37%{transform:translateY(0) scale(1.07,.76) rotate(1.5deg)}' +
        '53%{transform:translateY(0) scale(1.09,.75) rotate(-2deg)}' +
        '68%{transform:translateY(0) scale(1.07,.74) rotate(2deg)}' +
        '84%{transform:translateY(0) scale(1.1,.73) rotate(-2deg)}' +
        '100%{transform:translateY(0) scale(1.08,.72)}' +
        '}' +
        '.ui-squash-crouch{animation-name:ui-squash-crouch;transform-origin:50% 100%;animation-fill-mode:both}' +
        '@keyframes ui-squash-launch{' +
        '0%{transform:translateY(0) scale(1.08,.72)}' +
        '16%{transform:translateY(-46%) scale(.92,1.18)}' +
        '29%{transform:translateY(-58%) scale(.96,1.06)}' +
        '48%{transform:translateY(0) scale(1.12,.82)}' +
        '65%{transform:translateY(-14%) scale(.98,1.04)}' +
        '77%{transform:translateY(0) scale(1.05,.92)}' +
        '89%{transform:translateY(-4%) scale(1,1.01)}' +
        '100%{transform:translateY(0) scale(1,1)}' +
        '}' +
        '.ui-squash-launch{animation-name:ui-squash-launch;transform-origin:50% 100%}' +
        '.ui-spin-cw{animation-name:ui-spin;animation-timing-function:linear}' +
        '.ui-spin-ccw{animation-name:ui-spin-rev;animation-timing-function:linear}';
    document.head.appendChild(st);
}

function applyCssAnimationEffect(el, effect) {
    if (!el || !el.classList) return;
    if (el._uiCssAnimationLoopTimer) {
        clearTimeout(el._uiCssAnimationLoopTimer);
        el._uiCssAnimationLoopTimer = null;
    }
    if (el._uiCssAnimationEndHandler) {
        el.removeEventListener('animationend', el._uiCssAnimationEndHandler);
        el._uiCssAnimationEndHandler = null;
    }
    if (el._uiCssAnimationClasses) {
        el.classList.remove(...el._uiCssAnimationClasses);
        el._uiCssAnimationClasses = null;
        el.style.removeProperty('animation-delay');
        el.style.removeProperty('animation-iteration-count');
    }
    if (!effect?.enabled) return;
    const params = effect.params || {};
    const className = params.className || effect.source?.className;
    if (!className) return;
    ensureCssEffectProvider(effect.source?.provider || 'animate.css');
    ensureLocalCssAnimationKeyframes();
    const baseClass = params.baseClass || 'animate__animated';
    const classes = [baseClass, className];
    const timing = effect.timing || {};
    el.style.setProperty('--animate-duration', (timing.durationMs || 800) + 'ms');
    // animate.css 는 --animate-delay/--animate-repeat 을 animate__delay-*/animate__repeat-* 클래스에서만
    // 참조하므로(기본 animate__animated 는 미참조) 표준 속성을 직접 지정한다.
    el.style.animationDelay = (timing.delayMs || 0) + 'ms';
    el.style.animationIterationCount = String(timing.iteration || 1);
    el.classList.add(...classes);
    el._uiCssAnimationClasses = classes;
    if (params.loop) {
        const loopDelay = Math.max(0, timing.loopDelayMs ?? 600);
        el._uiCssAnimationEndHandler = () => {
            el.classList.remove(...classes);
            el._uiCssAnimationLoopTimer = setTimeout(() => {
                if (!el.isConnected) return;
                el.classList.add(...classes);
            }, loopDelay);
        };
        el.addEventListener('animationend', el._uiCssAnimationEndHandler);
    }
}

const _providerScriptPromises = {}; // id → Promise (CDN 폴백 시 엘리먼트를 재생성하므로 프라미스는 모듈 레벨에 보관)
function ensureEffectProviderScript(provider) {
    if (typeof document === 'undefined') return Promise.resolve(false);
    if (provider === 'canvas-confetti' && typeof window !== 'undefined' && window.confetti) return Promise.resolve(true);
    const entry = EFFECT_PROVIDER_SCRIPTS[provider];
    if (!entry) return Promise.resolve(false);
    const id = 'ui-effect-provider-script-' + provider.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
    if (_providerScriptPromises[id]) return _providerScriptPromises[id];
    const existing = document.getElementById(id);
    if (existing) return existing._loadPromise || Promise.resolve(true); // 외부/과거 주입분
    _providerScriptPromises[id] = loadScriptWithFallback(id, vendorUrl(entry.local), entry.cdn);
    return _providerScriptPromises[id];
}

function randomBetween(min, max) {
    return min + Math.random() * (max - min);
}

function ensureAmbientAuraKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-ambient-aura-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-ambient-aura-keyframes';
    st.textContent =
        '@keyframes ui-ambient-aura{' +
        '0%{transform:translate(-50%,-50%) translate(var(--x0),var(--y0)) scale(.2);opacity:0}' +
        '18%{opacity:.95}' +
        '70%{opacity:.55}' +
        '100%{transform:translate(-50%,-50%) translate(var(--x1),var(--y1)) scale(1);opacity:0}' +
        '}' +
        '.ui-ambient-aura{position:absolute;inset:0;pointer-events:none;overflow:visible;z-index:20}' +
        '.ui-ambient-aura-star{position:absolute;left:50%;top:50%;width:var(--s);height:var(--s);animation:ui-ambient-aura var(--d) ease-out infinite;animation-delay:var(--delay);filter:drop-shadow(0 0 5px rgba(255,255,255,.85))}' +
        '.ui-ambient-aura-star::before,.ui-ambient-aura-star::after{content:"";position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:rgba(255,255,255,.95);border-radius:999px}' +
        '.ui-ambient-aura-star::before{width:100%;height:28%}' +
        '.ui-ambient-aura-star::after{width:28%;height:100%}';
    document.head.appendChild(st);
}

function applyAmbientSparkleAura(el, effect) {
    if (typeof document === 'undefined' || !el) return;
    const old = el.querySelector?.(':scope > .ui-ambient-aura');
    if (old) old.remove();
    if (!effect?.enabled) return;
    ensureAmbientAuraKeyframes();
    const params = effect.params || {};
    const count = Math.max(1, Math.min(96, params.count || 18));
    const auraWidth = Math.max(10, params.auraWidth || 140);
    const auraHeight = Math.max(10, params.auraHeight || 140);
    const aura = document.createElement('span');
    aura.className = 'ui-ambient-aura';
    for (let i = 0; i < count; i++) {
        const star = document.createElement('span');
        star.className = 'ui-ambient-aura-star';
        const angle = Math.round((360 / count) * i + (i % 3) * 9);
        const radians = angle * Math.PI / 180;
        const distance = 0.68 + (i % 5) * 0.08;
        const x1 = Math.round(Math.cos(radians) * auraWidth * 0.5 * distance);
        const y1 = Math.round(Math.sin(radians) * auraHeight * 0.5 * distance);
        const size = (params.sizeMin || 0.45) + ((params.sizeMax || 0.9) - (params.sizeMin || 0.45)) * ((i % 5) / 4);
        const duration = 2200 + (i % 6) * 320;
        star.style.setProperty('--x0', Math.round(x1 * 0.34) + 'px');
        star.style.setProperty('--y0', Math.round(y1 * 0.34) + 'px');
        star.style.setProperty('--x1', x1 + 'px');
        star.style.setProperty('--y1', y1 + 'px');
        star.style.setProperty('--s', Math.round(size * 10) + 'px');
        star.style.setProperty('--d', duration + 'ms');
        star.style.setProperty('--delay', -(i * 180 % duration) + 'ms');
        aura.appendChild(star);
    }
    el.appendChild(aura);
}

// 힐링 오라 — 발밑에서 위로 피어오르는 녹빛 세로 광선(스핀들) + 십자가/점 (RPG 힐).
// ambient-aura 와 같은 내부 반복형: DOM+CSS 키프레임, 입자 배치는 결정적(i 기반)이라 재렌더에도 모양이 같다.
// 컨테이너에 ui-ambient-aura 클래스를 함께 달아 제거·상호배타 경로(:scope > .ui-ambient-aura)를 공유한다.
function ensureHealingAuraKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-heal-aura-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-heal-aura-keyframes';
    st.textContent =
        '@keyframes ui-heal-rise{' +
        '0%{transform:translate(-50%,0);opacity:0}' +
        '15%{opacity:.9}' +
        '70%{opacity:.55}' +
        '100%{transform:translate(-50%,var(--rise));opacity:0}' +
        '}' +
        '@keyframes ui-heal-streak{' +
        '0%{transform:translate(-50%,0) scaleY(.25);opacity:0}' +
        '20%{opacity:.85}' +
        '100%{transform:translate(-50%,var(--rise)) scaleY(1);opacity:0}' +
        '}' +
        '.ui-heal-aura{position:absolute;inset:0;pointer-events:none;overflow:visible;z-index:20}' +
        '.ui-heal-p{position:absolute;left:var(--x);bottom:var(--b);animation:ui-heal-rise var(--d) ease-out infinite;animation-delay:var(--delay)}' +
        '.ui-heal-streak{width:var(--w);height:var(--h);transform-origin:50% 100%;border-radius:999px;' +
        'background:linear-gradient(to top,rgba(140,255,170,0),rgba(205,255,215,.95) 45%,rgba(140,255,170,0));' +
        'filter:drop-shadow(0 0 4px rgba(120,255,160,.8));animation-name:ui-heal-streak}' +
        '.ui-heal-cross{width:var(--s);height:var(--s);filter:drop-shadow(0 0 5px rgba(120,255,160,.85))}' +
        '.ui-heal-cross::before,.ui-heal-cross::after{content:"";position:absolute;left:50%;top:50%;' +
        'transform:translate(-50%,-50%);background:rgba(215,255,225,.95);border-radius:2px}' +
        '.ui-heal-cross::before{width:100%;height:32%}' +
        '.ui-heal-cross::after{width:32%;height:100%}' +
        '.ui-heal-dot{width:var(--s);height:var(--s);border-radius:50%;background:rgba(205,255,220,.9);' +
        'filter:drop-shadow(0 0 4px rgba(120,255,160,.8))}';
    document.head.appendChild(st);
}

function applyHealingAura(el, effect) {
    if (typeof document === 'undefined' || !el) return;
    const old = el.querySelector?.(':scope > .ui-ambient-aura');
    if (old) old.remove();
    if (!effect?.enabled) return;
    ensureHealingAuraKeyframes();
    const params = effect.params || {};
    const count = Math.max(1, Math.min(96, params.count || 26));
    const auraWidth = Math.max(10, params.auraWidth || 150);
    const auraHeight = Math.max(10, params.auraHeight || 160);
    const sizeMin = params.sizeMin || 0.5, sizeMax = params.sizeMax || 1.1;
    const aura = document.createElement('span');
    aura.className = 'ui-ambient-aura ui-heal-aura';
    for (let i = 0; i < count; i++) {
        const p = document.createElement('span');
        // 구성비 — 세로 광선이 주역(~60%), 십자가(~25%)·점(~15%)이 엠비언트로 섞인다
        const kind = (i % 3 === 0) ? 'cross' : (i % 5 === 2) ? 'dot' : 'streak';
        p.className = 'ui-heal-p ui-heal-' + kind;
        const size = sizeMin + (sizeMax - sizeMin) * ((i % 5) / 4);
        const xOff = Math.round(((((i * 53) % 100) / 100) - 0.5) * auraWidth);
        const rise = Math.round(auraHeight * (0.55 + (i % 4) * 0.15));
        const duration = 1800 + (i % 7) * 260;
        p.style.setProperty('--x', `calc(50% + ${xOff}px)`);
        p.style.setProperty('--b', ((i * 29) % 12) + 'px');
        p.style.setProperty('--rise', -rise + 'px');
        p.style.setProperty('--d', duration + 'ms');
        p.style.setProperty('--delay', -(i * 230 % duration) + 'ms');
        if (kind === 'streak') {
            p.style.setProperty('--w', (2 + (i % 2)) + 'px');
            p.style.setProperty('--h', Math.round(auraHeight * (0.18 + (i % 5) * 0.08) * size) + 'px');
        } else {
            p.style.setProperty('--s', Math.round(size * (kind === 'cross' ? 14 : 5)) + 'px');
        }
        aura.appendChild(p);
    }
    el.appendChild(aura);
}

// 보물 광채 — 바닥 중심에서 부채꼴로 뻗은 금빛 광선 + 코어 글로우 + 상승 반짝임 (보물상자 개봉).
// healing-aura 와 같은 내부 반복형(DOM+CSS 키프레임, i 기반 결정적 배치). 모션 차이:
// heal 스트릭은 위로 '이동'하지만 이 광선은 바닥에 고정된 채 scaleY 로 '일렁'인다.
// 상승 반짝임과 컨테이너 규칙은 heal 스타일시트(ui-heal-p/ui-heal-rise/ui-heal-aura)를 재사용한다.
function ensureTreasureGlowKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-tg-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-tg-keyframes';
    st.textContent =
        '@keyframes ui-tg-beam{' +
        '0%,100%{transform:translateX(-50%) rotate(var(--a)) scaleY(.5);opacity:.2}' +
        '45%{transform:translateX(-50%) rotate(var(--a)) scaleY(1);opacity:.85}' +
        '}' +
        '@keyframes ui-tg-core{' +
        '0%,100%{opacity:.55;transform:translateX(-50%) scale(.85)}' +
        '50%{opacity:.95;transform:translateX(-50%) scale(1.1)}' +
        '}' +
        // heal-rise 와 달리 가로 드리프트(--dx) 포함 — 모트가 광선 부채꼴을 따라 벌어지며 상승한다
        '@keyframes ui-tg-rise{' +
        '0%{transform:translate(-50%,0);opacity:0}' +
        '15%{opacity:.9}' +
        '70%{opacity:.55}' +
        '100%{transform:translate(calc(-50% + var(--dx)),var(--rise));opacity:0}' +
        '}' +
        '.ui-tg-beam{position:absolute;left:var(--x);bottom:0;width:var(--w);height:var(--h);' +
        'transform-origin:50% 100%;border-radius:999px;' +
        'background:linear-gradient(to top,rgba(255,214,110,.95),rgba(255,242,205,.55) 45%,rgba(255,214,110,0));' +
        'filter:drop-shadow(0 0 6px rgba(255,200,90,.8));' +
        'animation:ui-tg-beam var(--d) ease-in-out infinite;animation-delay:var(--delay)}' +
        '.ui-tg-core{position:absolute;left:50%;bottom:-8px;transform:translateX(-50%);width:var(--w);height:var(--h);border-radius:50%;' +
        'background:radial-gradient(ellipse at center,rgba(255,236,170,.95),rgba(255,200,90,.45) 55%,rgba(255,200,90,0) 75%);' +
        'animation:ui-tg-core 1600ms ease-in-out infinite}' +
        '.ui-tg-mote{position:absolute;left:var(--x);bottom:var(--b);width:var(--s);height:var(--s);' +
        'border-radius:50%;background:rgba(255,240,200,.95);filter:drop-shadow(0 0 4px rgba(255,205,95,.9));' +
        'animation:ui-tg-rise var(--d) ease-out infinite;animation-delay:var(--delay)}';
    document.head.appendChild(st);
}

function applyTreasureGlow(el, effect) {
    if (typeof document === 'undefined' || !el) return;
    const old = el.querySelector?.(':scope > .ui-ambient-aura');
    if (old) old.remove();
    if (!effect?.enabled) return;
    ensureHealingAuraKeyframes();
    ensureTreasureGlowKeyframes();
    const params = effect.params || {};
    const count = Math.max(1, Math.min(96, params.count || 30));
    const auraWidth = Math.max(10, params.auraWidth || 150);
    const auraHeight = Math.max(10, params.auraHeight || 170);
    const sizeMin = params.sizeMin || 0.6, sizeMax = params.sizeMax || 1.2;
    const spread = params.spread ?? 44;
    const aura = document.createElement('span');
    aura.className = 'ui-ambient-aura ui-heal-aura';
    // 코어 글로우 — 상자 틈에서 새어나오는 빛 웅덩이
    const core = document.createElement('span');
    core.className = 'ui-tg-core';
    core.style.setProperty('--w', Math.round(auraWidth * 0.8) + 'px');
    core.style.setProperty('--h', Math.round(auraHeight * 0.22) + 'px');
    aura.appendChild(core);
    for (let i = 0; i < count; i++) {
        const p = document.createElement('span');
        const size = sizeMin + (sizeMax - sizeMin) * ((i % 5) / 4);
        if (i % 2 === 0) {
            // 광선 — 밑동을 Aura Width 에 걸쳐 가로 분산(상자 폭), Spread(총 방사각°)만큼 바깥으로 기울고 scaleY 로 일렁임
            p.className = 'ui-tg-beam';
            const duration = 1400 + (i % 5) * 300;
            const xNorm = (((i * 53) % 100) / 100) - 0.5;
            p.style.setProperty('--x', `calc(50% + ${Math.round(xNorm * auraWidth * 0.7)}px)`);
            p.style.setProperty('--a', Math.round(xNorm * spread + ((i * 37) % 9) - 4) + 'deg');
            p.style.setProperty('--w', (3 + (i % 3) * 2) + 'px');
            p.style.setProperty('--h', Math.round(auraHeight * (0.6 + (i % 4) * 0.13) * size) + 'px');
            p.style.setProperty('--d', duration + 'ms');
            p.style.setProperty('--delay', -(i * 310 % duration) + 'ms');
        } else {
            // 상승 반짝임 — 밑동은 광선 밑동과 동일 폭, 상승하며 방사각을 따라 바깥으로 드리프트(윗면 = 광선 윗면)
            p.className = 'ui-tg-mote';
            const duration = 1800 + (i % 7) * 260;
            const xNorm = (((i * 53) % 100) / 100) - 0.5;
            const rise = Math.round(auraHeight * (0.55 + (i % 4) * 0.15));
            p.style.setProperty('--x', `calc(50% + ${Math.round(xNorm * auraWidth * 0.7)}px)`);
            p.style.setProperty('--b', ((i * 29) % 12) + 'px');
            p.style.setProperty('--rise', -rise + 'px');
            p.style.setProperty('--dx', Math.round(Math.tan(xNorm * spread * Math.PI / 180) * rise) + 'px');
            p.style.setProperty('--d', duration + 'ms');
            p.style.setProperty('--delay', -(i * 230 % duration) + 'ms');
            p.style.setProperty('--s', Math.round(size * 5) + 'px');
        }
        aura.appendChild(p);
    }
    el.appendChild(aura);
}

// 방사형 스트릭 — 중심에서 바깥으로 가속하며 뻗는 '유한 길이' 광선. warp/manga 공용 단일 구현.
// 원근 투영(화면반지름 = k / z)의 CSS 근사: 반지름을 가속 곡선으로 밀면서 길이를 함께 키운다.
// conic-gradient 는 각도만의 함수라 확대해도 패턴이 제자리(자기닮음)이므로 쓰지 않는다 —
// 반지름 방향 이동이 성립하려면 광선마다 독립된 span 이어야 한다.
//   warp  : 얇고 균일한 빛줄기가 통째로 바깥으로 날아간다 (스타필드 하이퍼스페이스)
//   manga : 안쪽이 뾰족한 삼각형(clip-path). 바깥 끝은 요소 밖에 걸친 채 안쪽 끝만 물러나
//           중심 구멍이 벌어진다 — 만화 집중선 줌인
// healing-aura 와 같은 내부 반복형(DOM+CSS 키프레임, RAF 없음). 배치는 i 기반 결정적이라
// 재렌더에도 모양이 같고, 컨테이너에 ui-ambient-aura 클래스를 달아 제거 경로를 공유한다.
function ensureRadialStreakKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-radial-streak-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-radial-streak-keyframes';
    st.textContent =
        '@keyframes ui-radial-streak{' +
        '0%{transform:rotate(var(--a)) translateX(var(--r0)) scaleX(var(--s0));opacity:0}' +
        '14%{opacity:var(--o)}' +
        '72%{opacity:var(--o)}' +
        '100%{transform:rotate(var(--a)) translateX(var(--r1)) scaleX(var(--s1));opacity:0}' +
        '}' +
        // ambient-aura 스타일시트가 주입되지 않은 경우에도 자립하도록 기본 규칙을 직접 갖는다(healing-aura 와 동일).
        '.ui-streak-aura{position:absolute;inset:0;pointer-events:none;z-index:20}' +
        // overflow 만은 ambient-aura 의 visible 과 충돌 — 주입 순서가 불정이라 2-클래스로 확실히 덮는다.
        '.ui-ambient-aura.ui-streak-aura{overflow:hidden}' +
        // transform-origin 을 요소 중심에 두고 rotate→translateX→scaleX 순으로 합성하면
        // 광선은 반지름 [r, r + len×s] 구간을 차지한다(r 은 자기 너비 = --len 기준 %).
        '.ui-streak{position:absolute;left:50%;top:50%;width:var(--len);height:var(--w);' +
        'margin-top:calc(var(--w) * -0.5);transform-origin:0 50%;background:var(--c);' +
        'animation:ui-radial-streak var(--d) cubic-bezier(.55,0,.95,.45) infinite;animation-delay:var(--delay)}' +
        '.ui-streak-manga{clip-path:polygon(0 50%,100% 0,100% 100%)}' +
        // 모션 민감 사용자 — 애니메이션 없이 중심에서 모서리까지 뻗은 정지 집중선으로 대체
        '@media (prefers-reduced-motion:reduce){.ui-streak{animation:none;opacity:calc(var(--o) * .6);' +
        'transform:rotate(var(--a)) translateX(var(--r0)) scaleX(1)}}';
    document.head.appendChild(st);
}

function applyRadialStreaks(el, effect, kind) {
    if (typeof document === 'undefined' || !el) return;
    const old = el.querySelector?.(':scope > .ui-ambient-aura');
    if (old) old.remove();
    if (!effect?.enabled) return;
    ensureRadialStreakKeyframes();
    const params = effect.params || {};
    const manga = kind === 'manga';
    const count = Math.max(1, Math.min(96, params.count || (manga ? 40 : 60)));
    // 길이·반지름의 기준자 = 요소 half-diagonal(px). 이 값이면 어떤 종횡비에서도 모서리까지 닿는다.
    // transform:scale 로 축소 표시되는 씬에서도 어긋나지 않도록 getBoundingClientRect 가 아니라
    // 레이아웃 px 인 offsetWidth/Height 로 잰다. 레이아웃 전(0)이면 fallback.
    const unit = Math.round(Math.hypot(el.offsetWidth || 0, el.offsetHeight || 0) / 2) || 220;
    // Aura Width = 바깥 도달 범위(%), Aura Height = 중심 여백(%) — 둘 다 '방출 범위' 파라미터
    const reach = Math.max(10, params.auraWidth || 100) / 100;
    const hole = Math.max(10, params.auraHeight || 100) / 100;
    const colors = (params.colors && params.colors.length) ? params.colors : ['#ffffff'];
    // [시작 반지름%, 시작 길이배율, 끝 반지름%, 끝 길이배율] — % 와 배율 모두 unit 기준.
    // manga 는 시작부터 바깥 끝이 1.08 로 요소 밖에 걸쳐 있고 안쪽만 0.08→0.55 로 물러난다.
    const geo = manga ? [8, 1.00, 55, 0.75] : [4, 0.07, 100, 0.35];
    const baseMs = manga ? 900 : 1500;
    const aura = document.createElement('span');
    aura.className = 'ui-ambient-aura ui-streak-aura';
    aura.style.setProperty('--len', unit + 'px');
    for (let i = 0; i < count; i++) {
        const s = document.createElement('span');
        s.className = 'ui-streak' + (manga ? ' ui-streak-manga' : '');
        const d = baseMs + ((i * 61) % 5) * (manga ? 90 : 170);
        // 균등 분할 + i 기반 지터 — 규칙적인 바퀴살 격자 느낌을 없앤다
        s.style.setProperty('--a', ((360 / count) * i + ((i * 37) % 19) - 9).toFixed(1) + 'deg');
        s.style.setProperty('--r0', (geo[0] * hole).toFixed(1) + '%');
        s.style.setProperty('--s0', geo[1].toFixed(2));
        // 끝 반지름만 흔들어 광선들이 한 줄로 도착하지 않게 한다
        s.style.setProperty('--r1', (geo[2] * reach * (0.88 + ((i * 23) % 25) / 100)).toFixed(1) + '%');
        s.style.setProperty('--s1', geo[3].toFixed(2));
        s.style.setProperty('--w', (manga ? 3 + ((i * 43) % 12) : 1 + ((i * 43) % 3)) + 'px');
        s.style.setProperty('--o', (manga ? 0.55 + ((i * 71) % 45) / 100 : 0.40 + ((i * 71) % 60) / 100).toFixed(2));
        s.style.setProperty('--d', d + 'ms');
        s.style.setProperty('--delay', -((i * 137) % d) + 'ms');
        // warp 은 진행 방향(바깥)이 밝은 머리, 뒤가 꼬리 — manga 는 잉크처럼 단색
        const c = colors[i % colors.length];
        s.style.setProperty('--c', manga ? c : `linear-gradient(90deg,transparent,${c})`);
        aura.appendChild(s);
    }
    el.appendChild(aura);
}

// 소프트 글리터 낙하 레시피 — Sparkle 프리셋(fall)과 confetti 컴포넌트(glitter-fall)가
// 동일 물리(하강각/중력/감쇠/드리프트/시간차 6회 방출)를 공유하는 단일 구현.
// fire = canvas-confetti 발사 함수(전역 confetti 또는 create 인스턴스),
// makeOrigin = 0..1 정규화 시작점 생성기, cfg.isAlive = 대상 생존 체크.
function fireGlitterFallWaves(fire, makeOrigin, cfg) {
    const waves = 6;
    const per = Math.max(1, Math.round((cfg.count || 22) / waves));
    for (let i = 0; i < waves; i++) {
        setTimeout(() => {
            if (cfg.isAlive && !cfg.isAlive()) return;
            const opts = {
                particleCount: per,
                origin: makeOrigin(),
                startVelocity: cfg.startVelocity,
                angle: 270,
                spread: 40,
                gravity: 0.35,
                decay: 0.97,
                drift: randomBetween(-0.8, 0.8),
                ticks: cfg.ticks,
                scalar: cfg.scalar,
                disableForReducedMotion: true,
            };
            if (Array.isArray(cfg.colors) && cfg.colors.length) opts.colors = cfg.colors;
            if (Array.isArray(cfg.shapes) && cfg.shapes.length) opts.shapes = cfg.shapes;
            fire(opts);
        }, i * (cfg.intervalMs || 150));
    }
}

// template 별 발사 레시피 — 같은 canvas-confetti 라도 중력/방출각/방출 타이밍이 달라
// 실제 움직임이 구분된다. burst=방사 폭발, halo=무중력 확장 링, stream=상승 연속류,
// fall=상단 낙하 반짝이, confetti=포물선 색종이.
function playParticleEffect(el, effect) {
    if (!effect?.enabled || effect.trigger !== 'mount') return;
    // 저장된 계약에는 과거 provider(party.js)·template(sparkles)이 남아 있을 수 있으므로
    // presetId 로 최신 프리셋 정의를 재해석한다.
    const preset = getParticleEffectPreset(effect.params?.presetId || '');
    const template = preset?.template || effect.source?.template || 'burst';
    if (template === 'ambient-aura') {
        applyAmbientSparkleAura(el, effect);
        return;
    }
    if (template === 'healing-aura') {
        applyHealingAura(el, effect);
        return;
    }
    if (template === 'treasure-glow') {
        applyTreasureGlow(el, effect);
        return;
    }
    if (template === 'warp-streaks' || template === 'manga-focus-lines') {
        applyRadialStreaks(el, effect, template === 'manga-focus-lines' ? 'manga' : 'warp');
        return;
    }
    ensureEffectProviderScript('canvas-confetti').then(ok => {
        const confetti = typeof window !== 'undefined' ? window.confetti : null;
        if (!ok || !confetti || !el.isConnected) return;
        const params = effect.params || {};
        const rect = el.getBoundingClientRect();
        const vw = window.innerWidth || 1;
        const vh = window.innerHeight || 1;
        const origin = { x: (rect.left + rect.width / 2) / vw, y: (rect.top + rect.height / 2) / vh };
        const count = Math.max(1, params.count ?? 30);
        // 슬라이더는 party.js 시절의 px/s 단위를 유지 — canvas-confetti startVelocity 로 환산
        const velocity = Math.max(2, randomBetween(params.speedMin ?? 50, params.speedMax ?? 260) / 7);
        const lifeMin = params.lifetimeMin ?? 0.8;
        const lifeMax = params.lifetimeMax ?? 1.4;
        const ticks = Math.max(20, Math.round(randomBetween(lifeMin, lifeMax) * 60));
        const base = {
            particleCount: count,
            startVelocity: velocity,
            scalar: randomBetween(params.sizeMin ?? 0.6, params.sizeMax ?? 1.2),
            spread: params.spread ?? 70,
            ticks,
            origin,
            disableForReducedMotion: true,
        };
        if (Array.isArray(params.colors) && params.colors.length) base.colors = params.colors;
        if (Array.isArray(params.shapes) && params.shapes.length) base.shapes = params.shapes;
        // 시간차 방출 공용 루프(stream/fall) — 요소가 사라지면 중단
        const emitWaves = (waves, intervalMs, fire) => {
            for (let i = 0; i < waves; i++) {
                setTimeout(() => { if (el.isConnected) fire(i); }, i * intervalMs);
            }
        };
        if (template === 'halo') {
            // 무중력 링: 느리게 사방으로 확장하며 떠다니다 소멸
            confetti({ ...base, spread: 360, startVelocity: Math.max(2, velocity * 0.5), gravity: 0, decay: 0.94, drift: 0 });
        } else if (template === 'stream') {
            // 상승 스트림: 좁은 각도로 위를 향해 6회 시간차 방출, 좌우 드리프트
            emitWaves(6, 90, () => confetti({
                ...base,
                particleCount: Math.max(1, Math.round(count / 6)),
                angle: 90,
                gravity: 0.35,
                decay: 0.92,
                drift: randomBetween(-0.6, 0.6),
            }));
        } else if (template === 'fall') {
            // 낙하 반짝이: 컴포넌트 confetti glitter-fall 과 동일한 공용 레시피
            fireGlitterFallWaves(confetti, () => ({
                x: (rect.left + rect.width * Math.random()) / vw,
                y: Math.max(0, rect.top - rect.height * 0.2) / vh,
            }), {
                count,
                startVelocity: Math.max(1, velocity * 0.2),
                ticks,
                scalar: base.scalar,
                colors: base.colors,
                shapes: base.shapes,
                isAlive: () => el.isConnected,
            });
        } else if (template === 'confetti') {
            // 색종이: 위로 쏘아올려 중력 포물선 낙하(색 미지정 시 라이브러리 기본 팔레트)
            confetti({ ...base, angle: 90, gravity: 1.1, decay: 0.9 });
        } else {
            // burst(기본): 방사형 폭발 — 빠르고 짧게 퍼진 뒤 낙하
            confetti({ ...base, spread: params.spread ?? 360, gravity: 0.7, decay: 0.9 });
        }
    });
}

function ensureSpinKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-spin-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-spin-keyframes';
    st.textContent = '@keyframes ui-spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}@keyframes ui-spin-rev{from{transform:rotate(0deg)}to{transform:rotate(-360deg)}}';
    document.head.appendChild(st);
}

// Confetti 키프레임 1회 주입. 두 패턴 공용 — 시작 좌표와 방향 벡터(--dx/--dy)만 다름.
function ensureConfettiKeyframes() {
    if (typeof document === 'undefined') return;
    if (document.getElementById('ui-confetti-keyframes')) return;
    const st = document.createElement('style');
    st.id = 'ui-confetti-keyframes';
    st.textContent =
        '@keyframes ui-confetti-burst{' +
        '0%{transform:translate(0,0) rotate(0deg);opacity:1}' +
        '100%{transform:translate(var(--dx),var(--dy)) rotate(var(--rot));opacity:0}' +
        '}' +
        '@keyframes ui-confetti-orbit{' +
        '0%{transform:rotate(var(--a0)) translateX(0) scale(.9);opacity:1}' +
        '35%{opacity:1}' +
        '100%{transform:rotate(var(--a1)) translateX(var(--dist)) scale(.75);opacity:0}' +
        '}';
    document.head.appendChild(st);
}

// container 안에 파티클 div를 spawn 하고 CSS 애니메이션으로 재생.
// center-burst: 가운데에서 사방(또는 부채꼴)으로 터지며 페이드아웃.
// sides-launch: 좌하단/우하단 두 발사점에서 위쪽 사선(우상/좌상)으로 동시 발사.
// glitter-fall: CSS 파티클이 아니라 Sparkle fall 프리셋과 공용 canvas-confetti 레시피
//               (fireGlitterFallWaves)를 컨테이너 스코프 캔버스에 재생 — 구현 중복 금지.
function spawnConfettiParticles(container, opts) {
    if (!container) return;
    ensureConfettiKeyframes();
    const cw = opts.width || container.offsetWidth || 320;
    const ch = opts.height || container.offsetHeight || 240;
    const pattern = opts.confettiPattern || 'center-burst';
    const colors = (opts.colors && opts.colors.length) ? opts.colors
        : ['#ff3b3b','#ffd23b','#3bff7a','#3bb6ff','#c63bff','#ffffff'];
    const N = Math.max(1, Math.min(200, opts.particleCount || 40));
    const dur = opts.duration || 1800;
    const spread = opts.spread != null ? opts.spread : 360;
    const velocity = opts.velocity != null ? opts.velocity : 220;
    const sizeMin = opts.sizeMin || 6;
    const sizeMax = opts.sizeMax || 12;
    const shape = opts.shape || 'mixed';

    if (pattern === 'glitter-fall') {
        if (container._confettiCleanupId) { clearTimeout(container._confettiCleanupId); container._confettiCleanupId = null; }
        // 캔버스는 유지(루프 재생 시 낙하 중인 입자가 끊기지 않도록), CSS 파티클 잔재만 제거
        Array.from(container.children).forEach(n => { if (n.tagName !== 'CANVAS') n.remove(); });
        ensureEffectProviderScript('canvas-confetti').then(ok => {
            const lib = typeof window !== 'undefined' ? window.confetti : null;
            if (!ok || !lib || !container.isConnected) return;
            let canvas = container.querySelector(':scope > canvas');
            if (!canvas) {
                canvas = document.createElement('canvas');
                canvas.width = cw;
                canvas.height = ch;
                canvas.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;';
                container.appendChild(canvas);
                container._confettiFallFire = lib.create(canvas, { resize: false, useWorker: false });
            }
            fireGlitterFallWaves(container._confettiFallFire, () => ({ x: Math.random(), y: 0 }), {
                count: N,
                startVelocity: Math.max(1, velocity / 35),
                ticks: Math.max(20, Math.round(dur * 0.06)),
                scalar: randomBetween(sizeMin, sizeMax) / 10,
                colors,
                shapes: shape === 'circle' ? ['circle'] : shape === 'rect' ? ['square'] : ['square', 'circle'],
                intervalMs: Math.max(60, Math.round(dur * 0.4 / 6)),
                isAlive: () => container.isConnected,
            });
        });
        return;
    }

    container.innerHTML = '';
    if (container._confettiCleanupId) { clearTimeout(container._confettiCleanupId); container._confettiCleanupId = null; }

    for (let i = 0; i < N; i++) {
        const p = document.createElement('span');
        const dist = velocity * (0.6 + Math.random() * 0.6);
        let startX, startY, ang;
        const orbitMode = pattern === 'clear-orbit';

        if (orbitMode) {
            startX = cw / 2;
            startY = ch / 2;
            ang = (i / N) * Math.PI * 2;
        } else if (pattern === 'sides-launch') {
            // 절반은 좌하단(우상단으로), 나머지 절반은 우하단(좌상단으로) 발사
            const fromLeft = i < N / 2;
            startX = fromLeft ? cw * 0.10 : cw * 0.90;
            startY = ch * 0.90;
            const baseDeg = fromLeft ? -45 : -135; // up-right vs up-left
            const angDeg = baseDeg + (Math.random() - 0.5) * Math.min(spread, 90);
            ang = angDeg * Math.PI / 180;
        } else {
            // center-burst: 가운데에서 발사. spread>=360 이면 전방향, 아니면 위쪽 부채꼴.
            startX = cw / 2;
            startY = ch / 2;
            if (spread >= 360) {
                ang = Math.random() * Math.PI * 2;
            } else {
                const angDeg = -90 + (Math.random() - 0.5) * spread;
                ang = angDeg * Math.PI / 180;
            }
        }
        const dx = Math.cos(ang) * dist;
        const dy = Math.sin(ang) * dist;

        const rotEnd = (Math.random() - 0.5) * 720;
        const sz = randomBetween(sizeMin, sizeMax);
        const isCircle = orbitMode || shape === 'circle' || (shape === 'mixed' && Math.random() < 0.4);
        const aspect = isCircle ? 1 : 0.5;
        const color = colors[i % colors.length];
        const delay = orbitMode ? 0 : Math.random() * Math.min(120, dur * 0.06);
        const animName = orbitMode ? 'ui-confetti-orbit' : 'ui-confetti-burst';
        const timing = orbitMode ? 'ease-out' : 'cubic-bezier(.2,.7,.4,1)';

        p.style.cssText =
            'position:absolute;' +
            'left:' + startX + 'px;top:' + startY + 'px;' +
            (orbitMode ? 'margin-left:' + (-sz / 2) + 'px;margin-top:' + (-(sz * aspect) / 2) + 'px;' : '') +
            'width:' + sz + 'px;height:' + (sz * aspect) + 'px;' +
            'background:' + color + ';' +
            'border-radius:' + (isCircle ? '50%' : '1px') + ';' +
            'pointer-events:none;will-change:transform,opacity;' +
            'animation:' + animName + ' ' + dur + 'ms ' + timing + ' ' + delay + 'ms forwards;';
        p.style.setProperty('--dx', dx + 'px');
        p.style.setProperty('--dy', dy + 'px');
        p.style.setProperty('--rot', rotEnd + 'deg');
        p.style.setProperty('--a0', (ang * 180 / Math.PI) + 'deg');
        p.style.setProperty('--a1', ((ang * 180 / Math.PI) + 115 + (Math.random() - 0.5) * 24) + 'deg');
        p.style.setProperty('--dist', dist + 'px');
        container.appendChild(p);
    }

    container._confettiCleanupId = setTimeout(() => {
        container._confettiCleanupId = null;
        if (!container._confettiLoopId) container.innerHTML = '';
    }, dur + 400);
}

// confetti 재생 스케줄 공용 — 런타임 autoplay/트리거(playConfetti)와 에디터 미리보기가
// 동일 로직을 공유한다. loop=무한 반복, repeat=유한 횟수(loop 꺼짐일 때), loopDelay=휴식(초).
// 기존 무한 loop 주기(duration+200ms)와의 호환을 위해 loopDelay 기본값은 0.2초.
function runConfettiPlayback(container, opts, cfg = {}) {
    if (!container) return;
    if (container._confettiLoopId) { clearInterval(container._confettiLoopId); container._confettiLoopId = null; }
    (container._confettiRepeatIds || []).forEach(clearTimeout);
    container._confettiRepeatIds = [];
    spawnConfettiParticles(container, opts);
    const periodMs = (opts.duration || 1800) + Math.round((cfg.loopDelay ?? 0.2) * 1000);
    if (cfg.loop) {
        container._confettiLoopId = setInterval(() => spawnConfettiParticles(container, opts), periodMs);
    } else {
        const repeat = Math.max(1, parseInt(cfg.repeat || 1, 10));
        for (let i = 1; i < repeat; i++) {
            container._confettiRepeatIds.push(setTimeout(() => {
                if (container.isConnected) spawnConfettiParticles(container, opts);
            }, i * periodMs));
        }
    }
}

// 배경 무한 스크롤 keyframe (1회 주입). 단일 background layer 기준.
// from/to 의 background-position 픽셀 값을 keyframe 텍스트에 직접 박아 var() 보간 이슈를 피한다.
// 첫 호출 시 prefers-reduced-motion 글로벌 CSS 도 함께 1회 주입 (런타임/에디터 preview 양쪽 커버).
function ensureBgScrollKeyframes(dx, dy) {
    if (typeof document === 'undefined') return null;
    if (!document.getElementById('ui-bg-scroll-global')) {
        const gs = document.createElement('style');
        gs.id = 'ui-bg-scroll-global';
        gs.textContent = '@media (prefers-reduced-motion: reduce){.sr-bg-scroll{animation-play-state:paused !important;}}';
        document.head.appendChild(gs);
    }
    const id = `ui-bg-scroll-${dx}_${dy}`;
    if (document.getElementById(id)) return id;
    const st = document.createElement('style');
    st.id = id;
    st.textContent = `@keyframes ${id}{from{background-position:0 0}to{background-position:${dx}px ${dy}px}}`;
    document.head.appendChild(st);
    return id;
}

// 스크롤 방향 단위 벡터 (dx_unit, dy_unit) — +x 는 오른쪽, +y 는 아래.
// background-position 은 +x 가 이미지를 오른쪽으로 미는 효과 → 시각적으론 패턴이 오른쪽으로 흐름.
const BG_SCROLL_DIRS = {
    'right':      [ 1,  0],
    'down-right': [ 1,  1],
    'down':       [ 0,  1],
    'down-left':  [-1,  1],
    'left':       [-1,  0],
    'up-left':    [-1, -1],
    'up':         [ 0, -1],
    'up-right':   [ 1, -1],
};

// 패턴 셀 합성 캐시 — key: `${mode}|${urls}|${cell}|${pad}|${alpha}` → { dataUrl, w, h, cols } | Promise<...>
// 동일 조합은 1회만 canvas 합성, 이후 즉시 재사용 → 클라이언트 부하 최소화.
// brick 가로폭(bw)은 첫 이미지 자연 비율(naturalWidth/naturalHeight)로 자동 계산.
const PATTERN_TILE_CACHE = new Map();

// tint(재색칠) SVG 필터 dedup 캐시. 모바일 WebKit 은 filter:url(data:...) 형태의
// data-URI SVG 필터를 무시하므로, <filter> 를 문서에 인라인 등록하고 url(#id) 로 참조한다.
// key = mode|r,g,b|k2|k3 → 동일 설정은 필터 노드 1개를 공유(노드 무한 증가 방지).
const TINT_FILTER_CACHE = new Map();
let _tintFilterSeq = 0;

// 이미지 1~N 장을 격자에 고루 섞어 그린 합성 타일 dataURL 을 비동기 생성 (배경/마스크 tile·brick 공용 단일 소스).
// tile: cellW×cellH 셀 격자 + pad 여백(셀 중앙 배치). brick: cellH=벽돌 높이·폭은 첫 이미지 비율, 홀수 행 반 칸 stagger.
// 복수 이미지는 [0..N-1] 반복 덱을 시드 셔플로 균등 분배 — key 해시 시드라 같은 입력은 항상 같은 배치(캐시·재렌더 일치).
// alpha(0~1) 는 합성 시 globalAlpha 로 적용. onReady({ dataUrl, w, h, cols }) — 실패 시 미호출(호출자는 fallback 유지).
function buildPatternTileDataUrl(urls, mode, cellW, cellH, pad, alpha, onReady) {
    if (typeof document === 'undefined' || !urls.length) return;
    const key = `${mode}|${urls.join(',')}|${cellW}x${cellH}|${pad}|${alpha}`;
    const cached = PATTERN_TILE_CACHE.get(key);
    if (cached && cached.dataUrl) { onReady(cached); return; }
    if (cached && typeof cached.then === 'function') { cached.then(onReady).catch(() => {}); return; }
    const load = (url) => new Promise((resolve, reject) => {
        const img = new Image();
        if (!url.startsWith('data:')) img.crossOrigin = 'anonymous';
        img.onload = () => resolve(img);
        img.onerror = (e) => { console.error('[pattern] 이미지 로드 실패:', url, e); reject(e); };
        img.src = url;
    });
    const promise = Promise.all(urls.map(load)).then(imgs => {
        const brick = mode === 'brick';
        const bh = cellH;
        const bw = brick ? Math.max(1, Math.round(bh * ((imgs[0].naturalWidth || bh) / (imgs[0].naturalHeight || bh)))) : cellW;
        const cw = bw + pad, ch = bh + pad;   // 셀 1칸 = 이미지 + pad 여백
        const N = imgs.length;
        // 격자 칸수 — 단일 이미지는 최소(tile 1×1 / brick 2×2 stagger), 복수는 4×4 로 섞을 공간 확보
        const G = N === 1 ? (brick ? 2 : 1) : 4;
        // 시드 셔플 덱 — key 문자열 해시 시드의 mulberry32 로 결정적 셔플 (균등 분배 + 무작위 배치)
        let seed = 0;
        for (let i = 0; i < key.length; i++) seed = (seed * 31 + key.charCodeAt(i)) | 0;
        const rand = () => {
            seed = (seed + 0x6D2B79F5) | 0;
            let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
        const deck = Array.from({ length: G * G }, (_, i) => i % N);
        for (let i = deck.length - 1; i > 0; i--) {
            const j = Math.floor(rand() * (i + 1));
            [deck[i], deck[j]] = [deck[j], deck[i]];
        }
        const c = document.createElement('canvas');
        c.width = cw * G;
        c.height = ch * G;
        const ctx = c.getContext('2d');
        ctx.imageSmoothingEnabled = true;
        ctx.globalAlpha = alpha;
        for (let r = 0; r < G; r++) {
            // brick 홀수 행은 반 칸 밀기 — 좌측 wrap 은 col=-1(덱 인덱스는 mod G 로 우측 끝과 동일 이미지)이 커버
            const off = brick ? (r % 2) * (cw / 2) : 0;
            for (let col = off ? -1 : 0; col < G; col++) {
                const img = imgs[deck[r * G + ((col + G) % G)]];
                ctx.drawImage(img, col * cw + off + pad / 2, r * ch + pad / 2, bw, bh);
            }
        }
        const result = { dataUrl: c.toDataURL('image/png'), w: c.width, h: c.height, cols: G };
        PATTERN_TILE_CACHE.set(key, result);
        return result;
    }).catch(e => {
        console.error('[pattern] 합성 실패 (이미지 로드/CORS taint 가능성)', e);
        PATTERN_TILE_CACHE.delete(key);
        throw e;
    });
    PATTERN_TILE_CACHE.set(key, promise);
    promise.then(onReady).catch(() => {});
}

// ── 반복 패턴 채움 + 스크롤 (배경 bg image-tile/brick + 마스크 자식 Tile/Brick 공용 단일 소스) ──
// 무한 스크롤 적용. scroll = { enabled, direction, secPerTile, epoch? }. cycleW/H = 1 cycle 당 background-position 변화 px.
// tilesPerCycle: 1 cycle 이 지나가는 타일/벽돌 수 (tile=1, brick 합성타일=2). epoch(ms) 주면 리로드 간 위상 연속.
function applyPatternScroll(el, scroll, cycleW, cycleH, tilesPerCycle) {
    if (!el) return;
    if (el.classList) el.classList.remove('sr-bg-scroll');
    el.style.animation = '';
    el.style.animationDelay = '';
    if (!scroll || !scroll.enabled) return;
    const dir = BG_SCROLL_DIRS[scroll.direction];
    if (!dir) return;
    const dx = Math.round(dir[0] * cycleW);
    const dy = Math.round(dir[1] * cycleH);
    if (dx === 0 && dy === 0) return;
    const perTile = Math.max(0.5, Math.min(60, Number(scroll.secPerTile) || 4));
    const duration = perTile * Math.max(1, tilesPerCycle | 0);
    const id = ensureBgScrollKeyframes(dx, dy);
    if (!id) return;
    if (el.classList) el.classList.add('sr-bg-scroll');
    el.style.animation = `${id} ${duration}s linear infinite`;
    // 리로드(편집기 play view 재생성) 간 스크롤 위상 연속 — epoch(최초 재생 ms) 주어지면 경과분 음수 delay
    if (scroll.epoch) el.style.animationDelay = `-${(Date.now() - scroll.epoch) / 1000}s`;
}

// 반복 패턴(tile/brick)으로 el 을 채움 + 선택적 스크롤. 호출자가 el 의 크기/위치를 잡아둔다.
// opts: imageUrl 또는 imageUrls[](복수=고루 섞어 합성), mode('tile'|'brick'), cellW, cellH(brick=벽돌 높이),
//       pad(셀 간 여백 px, tile/brick 공통), alpha(0~1 이미지 불투명도), color(뒤 배경색),
//       scroll({enabled,direction,secPerTile,epoch}|null), stamp(비동기 합성 stale-guard 키 → el.dataset.patStamp).
// 합성은 비동기 — 완료 전 stamp 가 바뀌면(타입/이미지 변경) 콜백 무시.
function applyPatternFill(el, opts) {
    if (!el) return;
    const o = opts || {};
    const urls = (Array.isArray(o.imageUrls) ? o.imageUrls : [o.imageUrl]).filter(Boolean);
    const scroll = o.scroll || null;
    const stamp = o.stamp || '';
    if (el.classList) el.classList.remove('sr-bg-scroll');
    el.style.animation = '';
    el.style.animationDelay = '';
    if (el.dataset) el.dataset.patStamp = stamp;
    if (o.color) el.style.backgroundColor = o.color;
    if (!urls.length) { el.style.backgroundImage = 'none'; return; }
    const tw = Math.max(2, Math.round(o.cellW || 64)), th = Math.max(2, Math.round(o.cellH || 64));
    const pad = Math.max(0, Math.round(o.pad || 0));
    const alpha = Math.max(0, Math.min(1, o.alpha ?? 1));
    const setPattern = (url, w, h, cols) => {
        el.style.backgroundImage = `url('${url}')`;
        el.style.backgroundSize = `${w}px ${h}px`;
        el.style.backgroundRepeat = 'repeat';
        el.style.backgroundPosition = '0 0';
        applyPatternScroll(el, scroll, w, h, cols);
    };
    // 단일 tile + 무여백 + 불투명 → 합성 없이 원본 repeat (즉시 표시)
    if (o.mode !== 'brick' && urls.length === 1 && pad === 0 && alpha >= 1) { setPattern(urls[0], tw, th, 1); return; }
    // 합성 필요(brick/복수 이미지/pad/alpha) — 완료 전 fallback: tile=원본 1장 repeat, brick=이미지 없음(뒤 색만)
    if (o.mode === 'brick') {
        el.style.backgroundImage = 'none';
        el.style.backgroundRepeat = '';
        el.style.backgroundPosition = '';
        el.style.backgroundSize = '';
    } else {
        setPattern(urls[0], tw, th, 1);
    }
    buildPatternTileDataUrl(urls, o.mode === 'brick' ? 'brick' : 'tile', tw, th, pad, alpha, ({ dataUrl, w, h, cols }) => {
        if (el.dataset && el.dataset.patStamp !== stamp) return; // 그 사이 타입/이미지 갱신됨
        setPattern(dataUrl, w, h, cols);
    });
}

// 에디터 공식 지원 폰트 (Google Fonts). 프로젝트가 별도 로드하지 않아도 되도록 단일 출처.
export const EDITOR_FONTS_HREF = 'https://fonts.googleapis.com/css2?family=Lilita+One&family=Fredoka+One&family=Boogaloo&family=Righteous&family=Baloo+2:wght@800&family=Press+Start+2P&family=Orbitron:wght@700&family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap';

function ensureEditorFontsLoaded() {
    if (typeof document === 'undefined') return Promise.resolve(false);
    const existing = document.getElementById('scene-renderer-editor-fonts');
    // 과거 주입분(프라미스 미추적)은 로드 완료로 간주 — 신규 주입만 _loadPromise 로 추적
    if (existing) return existing._loadPromise || Promise.resolve(true);
    const head = document.head || document.getElementsByTagName('head')[0];
    if (!head) return Promise.resolve(false);
    // 로컬 vendor/fonts 우선(오프라인·웹뷰 대응), 실패 시에만 Google Fonts CDN 폴백.
    // (로컬이 기본 경로가 되면서 CDN preconnect 사전 힌트는 제거 — 폴백 시에만 원격 접속이 발생한다.)
    const link = document.createElement('link');
    link.id = 'scene-renderer-editor-fonts';
    link.rel = 'stylesheet';
    const p = loadStylesheetWithFallback(link, vendorUrl('fonts/fonts.css'), EDITOR_FONTS_HREF);
    head.appendChild(link);
    return p;
}

// ── Dynamic Tab Bar (navigation scene 전용) ─────────────────────────────────
// 동적 탭바 설정 기본값 단일 소스. 에디터 패널/컨트랙트 export/빌더가 모두 이 정규화를 거친다.
const NAV_TAB_BAR_DEFAULTS = {
    enabled: false,
    activeGrow: 160,        // 선택 탭 확장 비율 % (100 = 확장 없음)
    iconScale: 135,         // 선택 탭 아이콘 확대 % (100 = 그대로)
    iconLift: 6,            // 선택 탭 아이콘 상승 px (cross-axis)
    iconSize: 36,           // 아이콘 표시 크기 px
    labelMode: 'active',    // 'active'(선택 탭만) | 'always' | 'none'
    // 레이블 텍스트 스타일 — 레이어/컴포넌트 텍스트와 동일 필드(에디터 컨트롤·textAppearanceCss 공유).
    // 구버전 평면 필드(labelSize/labelColor)는 normalizeNavTabBar 에서 여기로 흡수된다.
    label: {
        fontSize: 12, fontWeight: '700', fontFamily: 'inherit', color: '#ffffff',
        textStrokeWidth: 0, textStrokeColor: '#000000',
        textDepthSize: 0, textDepthColor: '#000000',
        textShadowX: 0, textShadowY: 0, textShadowBlur: 0, textShadowColor: '#000000', textShadowOpacity: 0,
        offsetX: 0, offsetY: 0,   // 레이블 위치 미세 조절 px — 텍스트 오브젝트 offsetX/Y 와 동일 규약
        colorGradEnabled: false, colorGrad2: '#ffffff', colorGradAngle: 180,   // 채움 그라데이션 — 텍스트 오브젝트와 동일 규약
    },
    inactiveOpacity: 65,    // 비활성 탭 아이콘/라벨 불투명도 %
    duration: 350,          // 전환 애니메이션 ms
    overshoot: true,        // 살짝 튕기는 spring easing 사용
    indicator: {
        type: 'color',      // 'color' | 'image' — 이미지로 대체 가능
        color: '#3f86e0',
        assetId: null,      // 에디터 전용 (contract 에는 imagePath 로 export)
        exportPath: '',
        imagePath: '',      // contract/런타임용
        radius: 12,
        extendTop: 8,       // nav 바 밖으로 돌출 px (top 방향)
        extendBottom: 0,
        inset: 2,           // 탭 영역 대비 좌우 인셋 px
    },
};

// 동적 네비 바 배경 이미지 엘리먼트 빌더 — 에디터 캔버스 가이드와 런타임(_buildNavigationDOM)이 공유하는 단일 소스.
//   cfg: { stretch, sliceEnabled, sliceL/T/R/B, sliceScale, sliceRepeat } — 에디터 ss.navBgImage / contract navBgImage 동일 형태
//   src: 호출측이 해석한 이미지 URL (에셋캐시 vs _resolveAssetPath — buildNavTabBar 아이콘과 동일 규약)
//   w/h: 바 크기 px. 9-slice 는 imageSliceCssText(단일 소스) 재사용, 아니면 stretch=꽉 채움 / contain 배경.
// 반환 엘리먼트는 navBgColor 위에 겹치는 배경 레이어(색이 이미지 뒤 폴백) — 바의 첫 자식으로 삽입한다.
function buildNavBgEl(cfg, src, w, h, opts) {
    if (!cfg || !src) return null;
    const el = document.createElement('div');
    el.className = 'sr-nav-bg';
    let css = 'position:absolute;inset:0;pointer-events:none;';
    const style = normalizeImageStyleModel(cfg);
    const slice = imageSliceCssText(style, src, 1, 1, w, h);
    if (slice) css += slice;
    else css += `background:url('${src}') center/${style.stretch ? '100% 100%' : 'contain'} no-repeat;`;
    el.style.cssText = css;
    // opts.sliceBitmap — 런타임 전용 눈금 없는 단일 비트맵 교체(에디터 캔버스 가이드는 미전달 → 기존 유지)
    if (slice && opts?.sliceBitmap) applySliceBitmapUpgrade(el, style, src, 1, 1, w, h);
    return el;
}

function normalizeNavTabBar(cfg) {
    const c = cfg || {};
    const label = { ...NAV_TAB_BAR_DEFAULTS.label, ...(c.label || {}) };
    // 레거시 평면 필드(labelSize/labelColor) → label 텍스트 스타일로 흡수 (label 미보유 구데이터 한정)
    if (!c.label) {
        if (c.labelSize != null) label.fontSize = c.labelSize;
        if (c.labelColor) label.color = c.labelColor;
    }
    return {
        ...NAV_TAB_BAR_DEFAULTS,
        ...c,
        indicator: { ...NAV_TAB_BAR_DEFAULTS.indicator, ...(c.indicator || {}) },
        label,
    };
}

// navigation 씬 데이터 → 계약(contract)의 nav 전용 필드 — 에디터 buildSceneContract nav 분기와
// 에셋스토어 프리뷰(sceneToContract)가 공유하는 단일 소스. 저장본·라이브 씬 모두 입력 가능
// (에디터 전용 assetId 는 버리고 exportPath 만 imagePath/iconPath 로 export).
function navSceneContractFields(ss, vw) {
    return {
        sceneType: 'navigation',
        navAnchor: ss.navAnchor || 'bottom',
        navOffsetX: ss.navOffsetX || 0,
        navOffsetY: ss.navOffsetY || 0,
        navBarWidth: ss.navBarWidth || vw,
        navBarHeight: ss.navBarHeight || 80,
        navBgColor: ss.navBgColor || 'rgba(22,33,62,0.95)',
        // 배경 이미지 — 에디터 전용 assetId/enabled/편집용 width·height 는 제외하고 imagePath(exportPath) 로 export (인디케이터와 동일 규약)
        navBgImage: (() => {
            const nb = ss.navBgImage;
            if (!nb || !nb.enabled || !(nb.exportPath || nb.assetId)) return null;
            const { assetId, enabled, exportPath, width, height, ...rest } = nb;
            return { ...rest, imagePath: exportPath || '' };
        })(),
        transitionType: ss.transitionType || 'slide',
        transitionDuration: ss.transitionDuration || 300,
        defaultTabId: ss.defaultTabId || ((ss.tabs && ss.tabs[0]) ? ss.tabs[0].id : ''),
        navTabBar: (() => {
            const tb = normalizeNavTabBar(ss.navTabBar);
            const { assetId, exportPath, ...indRest } = tb.indicator;
            return { ...tb, indicator: { ...indRest, imagePath: exportPath || '' } };
        })(),
        tabs: (ss.tabs || []).map(t => ({
            id: t.id, label: t.label || t.id, sceneName: t.sceneName || '',
            iconPath: t.iconExportPath || '', iconActivePath: t.iconActiveExportPath || ''
        })),
    };
}

/**
 * 동적 탭바 DOM 빌더 — 에디터 캔버스 미리보기와 런타임(_buildNavigationDOM)이 공유하는 단일 소스.
 * 선택 탭 확장(flex-grow) · 아이콘 확대/상승 · 밝은 인디케이터(색/이미지) 슬라이드를
 * 동일한 duration/easing 으로 묶어 하나의 전환처럼 재생한다.
 *
 * 인디케이터 위치는 % 기반(calc)이라 바 크기와 무관하게 동작한다.
 * 아이콘/인디케이터 이미지 URL 해석(에셋캐시 vs _resolveAssetPath)은 호출측 책임.
 *
 * @param {object} opts
 *   tabs: [{ id, label, iconSrc, iconActiveSrc }]  — iconSrc 없으면 라벨만 표시
 *   config: navTabBar 설정 (normalizeNavTabBar 자동 적용)
 *   indicatorSrc: 인디케이터 이미지 URL ('' 이면 config.indicator.color 사용)
 *   vertical: nav anchor 가 left/right 일 때 true (세로 배치)
 *   activeTabId: 초기 활성 탭 id
 *   onTabClick: (tabId) => void — 탭 클릭 콜백 (미리보기: setActive, 런타임: switchTab)
 * @returns {{ el: HTMLElement, setActive(tabId: string): void }}
 */
function buildNavTabBar(opts) {
    const cfg = normalizeNavTabBar(opts.config);
    const tabs = opts.tabs || [];
    const vertical = !!opts.vertical;
    const grow = Math.max(1, (cfg.activeGrow || 100) / 100);
    const ease = cfg.overshoot ? 'cubic-bezier(.34,1.3,.5,1)' : 'ease';
    const trans = `${cfg.duration}ms ${ease}`;
    const ind = cfg.indicator;

    const bar = document.createElement('div');
    bar.className = 'sr-nav-tabbar';
    bar.style.cssText = `position:absolute;inset:0;display:flex;flex-direction:${vertical ? 'column' : 'row'};align-items:stretch;overflow:visible;`;

    // 인디케이터 레이어 — cross-axis 는 extendTop/Bottom 만큼 바 밖으로 돌출 가능
    const indEl = document.createElement('div');
    indEl.className = 'sr-nav-tabbar-indicator';
    {
        let css = 'position:absolute;pointer-events:none;';
        css += vertical
            ? `left:${-ind.extendTop}px;right:${-ind.extendBottom}px;`
            : `top:${-ind.extendTop}px;bottom:${-ind.extendBottom}px;`;
        if (opts.indicatorSrc) {
            css += `background:url('${opts.indicatorSrc}') no-repeat center;background-size:100% 100%;`;
        } else {
            css += `background:${ind.color};border-radius:${ind.radius}px;`;
        }
        const prop = vertical ? 'top, height' : 'left, width';
        css += `transition:${prop.split(', ').map(p => `${p} ${trans}`).join(', ')};`;
        indEl.style.cssText = css;
    }
    bar.appendChild(indEl);

    const tabEls = [];
    tabs.forEach(t => {
        const btn = document.createElement('div');
        btn.className = 'sr-nav-tabbar-tab';
        btn.dataset.navTab = t.id;
        btn.style.cssText = `position:relative;flex:1 1 0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;cursor:pointer;overflow:visible;transition:flex-grow ${trans};-webkit-tap-highlight-color:transparent;`;

        let iconEl = null;
        if (t.iconSrc) {
            iconEl = document.createElement('img');
            iconEl.src = t.iconSrc;
            iconEl.draggable = false;
            iconEl.style.cssText = `width:${cfg.iconSize}px;height:${cfg.iconSize}px;object-fit:contain;transition:transform ${trans},opacity ${trans};pointer-events:none;`;
        }
        if (iconEl) btn.appendChild(iconEl);

        let labelEl = null;
        if (cfg.labelMode !== 'none') {
            labelEl = document.createElement('span');
            labelEl.textContent = t.label || t.id;
            // 외관은 텍스트 오브젝트와 동일한 단일 소스(textAppearanceCss) — 폰트·색·외곽선·깊이·그림자.
            // 위치는 offsetX/Y(px) translate — setActive 는 opacity/max-height 만 만지므로 충돌 없음.
            const _lofX = cfg.label.offsetX || 0, _lofY = cfg.label.offsetY || 0;
            labelEl.style.cssText = `${textAppearanceCss(cfg.label)}line-height:1.2;white-space:nowrap;transition:opacity ${trans},max-height ${trans};overflow:hidden;pointer-events:none;`
                + ((_lofX || _lofY) ? `transform:translate(${_lofX}px,${_lofY}px);` : '');
            applyTextGradientOverlay(labelEl, cfg.label);
            btn.appendChild(labelEl);
        }

        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            if (opts.onTabClick) opts.onTabClick(t.id);
        });
        bar.appendChild(btn);
        tabEls.push({ id: t.id, btn, iconEl, labelEl, iconSrc: t.iconSrc || '', iconActiveSrc: t.iconActiveSrc || '' });
    });

    const setActive = (tabId) => {
        const n = tabEls.length;
        if (!n) return;
        let activeIdx = tabEls.findIndex(te => te.id === tabId);
        if (activeIdx < 0) activeIdx = 0;
        const unit = 100 / (n - 1 + grow);
        // 인디케이터 목표 위치 — flex-grow 전환과 동일 easing 이라 탭 확장과 동기 이동
        const startPct = activeIdx * unit;
        const sizePct = unit * grow;
        if (vertical) {
            indEl.style.top = `calc(${startPct}% + ${ind.inset}px)`;
            indEl.style.height = `calc(${sizePct}% - ${ind.inset * 2}px)`;
        } else {
            indEl.style.left = `calc(${startPct}% + ${ind.inset}px)`;
            indEl.style.width = `calc(${sizePct}% - ${ind.inset * 2}px)`;
        }
        tabEls.forEach((te, i) => {
            const active = i === activeIdx;
            te.btn.style.flexGrow = active ? grow : 1;
            te.btn.classList.toggle('active', active);
            const fade = (cfg.inactiveOpacity ?? 100) / 100;
            if (te.iconEl) {
                const lift = vertical ? `translateX(${active ? -cfg.iconLift : 0}px)` : `translateY(${active ? -cfg.iconLift : 0}px)`;
                te.iconEl.style.transform = `${lift} scale(${active ? (cfg.iconScale || 100) / 100 : 1})`;
                te.iconEl.style.opacity = active ? '1' : String(fade);
                if (te.iconActiveSrc) te.iconEl.src = active ? te.iconActiveSrc : te.iconSrc;
            }
            if (te.labelEl) {
                const show = cfg.labelMode === 'always' || active;
                te.labelEl.style.opacity = show ? (active ? '1' : String(fade)) : '0';
                te.labelEl.style.maxHeight = show ? `${cfg.label.fontSize + 6 + (cfg.label.textDepthSize || 0)}px` : '0';
            }
        });
    };

    setActive(opts.activeTabId || (tabs[0] && tabs[0].id));
    return { el: bar, setActive };
}

export class SceneRenderer {

    /** 에디터 공식 폰트 stylesheet URL (단일 출처). */
    static get EDITOR_FONTS_HREF() { return EDITOR_FONTS_HREF; }

    /** 에디터 공식 폰트를 <head>에 1회 주입. 프로젝트에서 명시적으로도 호출 가능. */
    static ensureFontsLoaded() { ensureEditorFontsLoaded(); }

    /**
     * @param {HTMLElement} container
     * @param {object} [options]
     * @param {string} [options.basePath] - 이미지 경로 앞에 붙일 prefix. 예) 'assets/'
     * @param {boolean} [options.autoLoadFonts=true] - 에디터 폰트 자동 로드. false로 끄면 프로젝트가 직접 로드해야 함.
     */
    constructor(container, options = {}) {
        if (options.autoLoadFonts !== false) ensureEditorFontsLoaded();
        this.container = container;
        this._basePath = (options && options.basePath) ? options.basePath : '';
        this._contract = null;
        this._el = null;
        this._styleEl = null;
        this._activeTab = null;
        this._handlers = {};       // eventName → Set<Function>
        this._boundElements = {};  // bindingKey → HTMLElement[]
        this._boundImages = {};    // imageKey → HTMLImageElement[]
        this._dataValues = {};     // 평탄화된 bindingKey → 마지막 값. show() 이전 update()도 누적되어
                                   //   _buildDOM 첫 페인트에 실제값을 시드 → 디폴트 literal 플리커 방지.
                                   //   reload/재마운트 시 _boundElements는 리셋해도 이건 유지한다.
        this._groupWrappers = {};  // groupName → HTMLElement
        this._widgets = {};        // 위젯 key → [{type,...}] — 그룹 위젯(토글/슬라이더) 표시 바인딩
        // Navigation scene 전용
        this._sceneRegistry = (options && options.sceneRegistry) || null; // { sceneName: contract }
        this._sceneFetch    = (options && options.sceneFetch) || null;    // (sceneName) => Promise<contract>
        this._navHostEl     = null;
        this._navHostInner  = null; // 현재 활성 매칭 씬 렌더 컨테이너
        this._navHostRenderer = null; // SceneRenderer instance for matched scene
        // 네비바가 가리는 영역(px) — 스크롤시 콘텐츠가 가려지지 않게 viewport 에서 차감
        this._safeArea = (options && options.safeArea) || { top: 0, bottom: 0, left: 0, right: 0 };
        // Scale-with-screen: 최상위 풀스크린 마운트 시 디자인 박스를 화면 비율에 맞춰 통째 스케일
        this._fitEl = null;
        this._designW = 0;
        this._designH = 0;
        this._onResize = null;
        this._hideTimer = null;    // hide() 전환 대기 타이머 — show()/reload() 가 대기 중이면 즉시 마감
        // introAnimations:false — 씬 타임라인(sceneAnimations)·1회성 등장 css 애니·초기 탭 슬라이드를
        // 건너뛰고 최종 상태로 즉시 표시(loop 형 상시 연출은 유지). 에디터 플레이뷰의 자동 리프레시가
        // 매번 등장 연출을 재생하지 않게 하는 용도. 기본 true — 게임 동작 불변.
        this._introAnimations = options.introAnimations !== false;
        // sliceBitmap:false — 9-slice 단일 비트맵 합성(applySliceBitmapUpgrade) 비활성.
        // 에디터 에디트 뷰 전용(실시간 리사이즈 중 합성 비용 0). 기본 true — 플레이뷰/게임은 눈금 없는 합성 렌더.
        this._sliceBitmap = options.sliceBitmap !== false;
        // wiringAudit:false — show() 후 흐름 연결 이벤트 미구독 자가진단 비활성.
        // 에디터 플레이뷰 전용(에디터는 게임 배선이 없는 게 정상). 기본 true — 게임에서 자동 진단.
        this._wiringAudit = options.wiringAudit !== false;
    }

    /** 매칭 씬 contract 사전 등록 (Live preview / 인라인 임베드용). */
    setSceneRegistry(registry) { this._sceneRegistry = registry || {}; return this; }
    /** 매칭 씬 contract 를 비동기로 가져오는 콜백 등록 (서버 fetch 용). */
    setSceneFetch(fn) { this._sceneFetch = fn; return this; }

    /**
     * sceneRegistry/sceneFetch 미주입 시 기본 해석기 — publish 산출물 scenes-index.json(이 모듈 옆)으로
     * 탭 씬 이름 → contract 를 해석한다. 게임이 옵션 주입을 잊어도 nav 탭이 마운트되게 하는 폴백이며,
     * 인덱스는 모듈 단위로 1회만 fetch(정적 캐시). 명시 옵션이 항상 우선.
     */
    static _fetchDefaultSceneIndex() {
        if (!SceneRenderer._sceneIndexPromise) {
            SceneRenderer._sceneIndexPromise = fetch(MODULE_BASE + 'scenes-index.json')
                .then(r => { if (!r.ok) throw new Error('scenes-index.json HTTP ' + r.status); return r.json(); });
        }
        return SceneRenderer._sceneIndexPromise;
    }
    _defaultSceneFetch(sceneName) {
        if (!MODULE_BASE) return Promise.reject(new Error('모듈 경로를 알 수 없어 기본 해석 불가 — sceneRegistry/sceneFetch 옵션을 주입하세요.'));
        return SceneRenderer._fetchDefaultSceneIndex().then(idx => {
            const hit = (idx.scenes || []).find(s => s.name === sceneName);
            if (!hit) throw new Error('scenes-index.json 에 씬이 없습니다: ' + sceneName + ' — 미publish 이거나 이름이 바뀌었을 수 있습니다.');
            return fetch(MODULE_BASE + hit.contract)
                .then(r => { if (!r.ok) throw new Error(hit.contract + ' HTTP ' + r.status); return r.json(); });
        });
    }

    // ── 공개 식별자 / 네비 접근자 (게임 코드는 내부 `_` 필드 대신 이것을 사용) ──
    /** 로드된 contract 의 sceneId (없으면 null). */
    get sceneId() { return this._contract?.sceneId ?? null; }
    /** 로드된 contract 의 sceneName (없으면 null). 이름은 rename 될 수 있음 — 영속 참조는 sceneUuid 로. */
    get sceneName() { return this._contract?.sceneName ?? null; }
    /** 로드된 contract 의 불변 sceneUuid (없으면 null). */
    get sceneUuid() { return this._contract?.sceneUuid ?? null; }
    /** navigation 씬 전용 — 현재 활성 탭에 마운트된 자식 SceneRenderer (없으면 null). 탭 전환 통지는 `nav:tabchange` 이벤트 구독. */
    getActiveTabRenderer() { return this._navHostRenderer; }

    /** 자신이 navigation scene 일 때, 자식 씬에 전달할 safeArea (가려진 영역 px). */
    _computeNavSafeArea() {
        const c = this._contract;
        if (c?.sceneType !== 'navigation') return { top:0, bottom:0, left:0, right:0 };
        const nh = c.navBarHeight || 80;
        const ox = c.navOffsetX || 0;
        const oy = c.navOffsetY || 0;
        switch (c.navAnchor || 'bottom') {
            case 'top':    return { top: nh + oy, bottom: 0, left: 0, right: 0 };
            case 'bottom': return { top: 0, bottom: nh + oy, left: 0, right: 0 };
            case 'left':   return { top: 0, bottom: 0, left: nh + ox, right: 0 };
            case 'right':  return { top: 0, bottom: 0, left: 0, right: nh + ox };
        }
        return { top:0, bottom:0, left:0, right:0 };
    }

    // ── Loading ───────────────────────────────────────────────────────────────

    /** URL에서 JSON을 fetch해서 로드. Promise 반환. */
    async load(url) {
        const resp = await fetch(url);
        if (!resp.ok) throw new Error(`[SceneRenderer] contract 로드 실패(HTTP ${resp.status}): ${url}`);
        this._contract = await resp.json();
        return this;
    }

    /** 이미 파싱된 계약 객체를 동기적으로 로드. */
    loadSync(contractObj) {
        this._contract = contractObj;
        return this;
    }

    // ── Scale-with-screen ───────────────────────────────────────────────────
    // 비율만 맞으면 화면 크기에 무관하게 배치되도록, 디자인 박스를 화면에 맞춰 통째로 스케일.
    // 최상위 풀스크린 마운트(container === document.body/documentElement)일 때만 적용한다.
    // navigation host 합성/인라인 임베드(자식 렌더러)는 비-body 컨테이너이므로 기존 동작을 유지한다.

    /** this._el 을 컨테이너에 마운트. 최상위면 fit 래퍼로 감싸 스케일, 아니면 그대로 append. */
    _mountFit() {
        const cont = this.container;
        const topLevel = cont === document.body || cont === document.documentElement;
        if (!topLevel) { cont.appendChild(this._el); this._fitEl = null; return; }

        const c = this._contract;
        let dw, dh;
        if (c.sceneType === 'navigation') {
            dw = c.viewport?.width || 390; dh = c.viewport?.height || 844;
        } else {
            dw = c.canvas?.width || 390; dh = c.viewport?.height || c.canvas?.height || 844;
        }
        const fit = document.createElement('div');
        fit.className = 'sr-fit';
        fit.style.cssText = `position:fixed;top:0;left:0;width:${dw}px;height:${dh}px;transform-origin:top left;`;
        fit.appendChild(this._el);
        this._fitEl = fit;
        this._designW = dw; this._designH = dh;
        cont.appendChild(fit);
        this._applyScreenFit();
        this._onResize = () => this._applyScreenFit();
        window.addEventListener('resize', this._onResize);
    }

    /** 디자인 박스(_designW×_designH)를 가용 영역에 비율 유지로 맞추고 중앙 정렬. */
    _applyScreenFit() {
        const fit = this._fitEl;
        if (!fit) return;
        const cont = this.container;
        const useWin = cont === document.body || cont === document.documentElement;
        const availW = useWin ? window.innerWidth  : cont.clientWidth;
        const availH = useWin ? window.innerHeight : cont.clientHeight;
        if (!availW || !availH || !this._designW || !this._designH) return;
        const scale = Math.min(availW / this._designW, availH / this._designH);
        const tx = (availW - this._designW * scale) / 2;
        const ty = (availH - this._designH * scale) / 2;
        fit.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
    }

    /** fit 래퍼/리스너 정리 후 마운트된 노드를 DOM 에서 제거. */
    _unmountFit() {
        if (this._onResize) { window.removeEventListener('resize', this._onResize); this._onResize = null; }
        const node = this._fitEl || this._el;
        if (node?.parentNode) node.parentNode.removeChild(node);
        this._fitEl = null;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    show() {
        if (!this._contract) throw new Error('SceneRenderer: load() 또는 loadSync()를 먼저 호출하세요.');
        if (this._hideTimer) {
            // hide() 전환 대기 중 재표시 — 대기 타이머가 새 DOM을 지우지 않도록 옛 DOM을 지금 마감한다.
            clearTimeout(this._hideTimer);
            this._hideTimer = null;
            this._finalizeHide();
        } else if (this._el) {
            console.warn('[SceneRenderer] show() 무시 — 이미 표시 중입니다. 계약 교체는 reload() 사용.', { sceneId: this._contract?.sceneId });
            return this;
        }
        this._buildDOM();
        this._mountFit();
        // 공개(reveal)만 리소스 준비 뒤로 지연 — 빌드/마운트는 동기 유지(직후 getElementById 등 호환).
        // 준비 전에 공개하면 등장형 이펙트 대상이 원본 그대로 노출되고(animate.css 미도착),
        // 특수 폰트는 폴백으로 그려졌다 교체(FOUT)된다. 루트는 opacity:0 으로 시작하므로 그동안 안 보임.
        this._whenRenderResourcesReady().then(() => {
            if (!this._rootEl?.isConnected) return; // 대기 중 hide()/reload() 된 경우
            requestAnimationFrame(() => {
                if (!this._rootEl?.isConnected) return;
                this._rootEl.classList.add('visible');
                this._rootEl.style.opacity = '1';
                if (this._introAnimations) this._runSceneAnimations();
            });
        });
        // 배선 자가진단 — 공개 후 잠시 뒤(늦은 구독 허용) 흐름 연결 이벤트의 미구독을 일괄 보고.
        // 클릭해야만 알 수 있던 "죽은 버튼"을 씬을 열기만 해도 드러낸다. 판정은 클릭 경고와 동일 로직.
        if (this._wiringAudit) {
            setTimeout(() => this._auditFlowWiring(), WIRING_AUDIT_DELAY_MS);
        }
        return this;
    }

    /**
     * 흐름 연결 배선 자가진단 — contract 가 씬 이동을 선언한(targetSceneUuid/branches) 이벤트마다
     * 게임 구독(on)이 있는지 검사한다. 미배선이 있으면 그룹 콘솔 경고 1회 + 전역 window.__uiWiringAudit
     * 에 씬 단위로 누적한다(게임 AI 되먹임용 — prompt.md 의 배선 수리 절차가 이 JSON 을 소비).
     * navigation 탭 씬은 sub-renderer 가 자기 show() 에서 각자 진단한다.
     */
    _auditFlowWiring() {
        if (!this._rootEl?.isConnected || !this._contract) return; // 진단 전에 hide()/reload() 된 경우
        const missing = [];
        (this._contract.layers || []).forEach(layer => {
            (layer.events || []).forEach(ev => {
                const evtName = ev.eventName || (layer.stableId + ':' + (ev.trigger || 'click'));
                if (!this._isFlowEventUnwired(ev, evtName)) return;
                missing.push({
                    eventName: evtName,
                    stableId: layer.stableId,
                    layerName: layer.displayName || '',
                    targets: ev.targetSceneUuid
                        ? [{ toSceneUuid: ev.targetSceneUuid, condition: null }]
                        : (ev.branches || []).map(b => ({ toSceneUuid: b.targetSceneUuid, toSceneName: b.targetSceneName || '', condition: b.condition || 'else' })),
                });
            });
        });
        if (typeof window !== 'undefined') {
            const audit = window.__uiWiringAudit = window.__uiWiringAudit || { note: '흐름도 연결 이벤트 미구독(게임 미배선) 자가진단 — 씬 표시 시점 기준. 배선 절차는 prompt.md 참조.', scenes: {} };
            const key = this._contract.sceneName || this._contract.sceneId || '?';
            if (missing.length) audit.scenes[key] = missing;
            else delete audit.scenes[key]; // 재표시 때 배선이 완료됐으면 지난 기록을 걷어낸다
        }
        if (!missing.length) return;
        // 공통 문구 헤더 1회 + 항목 나열 (리포트류 출력 그룹핑 관례)
        console.warn('[SceneRenderer] 배선 자가진단: 흐름도 연결 이벤트 ' + missing.length + '건에 구독자가 없습니다(게임 미배선) — 씬 "'
            + (this._contract.sceneName || this._contract.sceneId) + '". 각 eventName 을 renderer.on()/PopupManager on:{} 으로 배선하세요.'
            + ' 전체 결과: JSON.stringify(window.__uiWiringAudit, null, 2)');
        missing.forEach(m => console.warn('  - ' + m.eventName + ' (' + (m.layerName || m.stableId) + ') → '
            + m.targets.map(t => (t.toSceneName || t.toSceneUuid || '?') + (t.condition ? ' [' + t.condition + ']' : '')).join(', ')));
    }

    /** 흐름도에서 씬 이동이 선언된 이벤트인데 구독자가 없는지 — 클릭 경고와 show 자가진단이 공유하는 단일 판정. */
    _isFlowEventUnwired(ev, evtName) {
        return !!(ev.targetSceneUuid || ev.branches) && !(this._handlers[evtName] && this._handlers[evtName].size);
    }

    /**
     * 첫 공개 전에 렌더 리소스가 준비될 때까지 대기하는 프라미스.
     * - 이펙트 CSS: _buildDOM 중 주입된 provider stylesheet(animate.css 등)의 로드 완료
     * - 웹폰트: contract 텍스트가 쓰는 font-family 들을 document.fonts.load 로 선로딩
     * RENDER_RESOURCE_TIMEOUT_MS 초과 시 경고 로그 후 resolve (무한 대기 금지). 항상 resolve, reject 없음.
     */
    _whenRenderResourcesReady() {
        if (typeof document === 'undefined') return Promise.resolve();
        const waits = [];
        document.querySelectorAll('link[id^="ui-css-effect-provider-"]').forEach(l => {
            if (l._loadPromise) waits.push(l._loadPromise);
        });
        if (document.fonts?.load) {
            const fontSpecs = new Set();
            (this._contract?.layers || []).forEach(l => (l.texts || []).forEach(t => {
                if (t.fontFamily) fontSpecs.add(`${t.fontWeight || 'bold'} 16px ${t.fontFamily}`);
            }));
            // 동적 탭바 레이블 폰트도 동일 선로딩 ('inherit'은 로드 대상 아님)
            const navLbl = this._contract?.navTabBar?.label;
            if (navLbl?.fontFamily && navLbl.fontFamily !== 'inherit') {
                fontSpecs.add(`${navLbl.fontWeight || 'bold'} 16px ${navLbl.fontFamily}`);
            }
            if (fontSpecs.size) {
                // 폰트 stylesheet(@font-face) 도착 후 실제 폰트 파일까지 선로딩. 미지원 폰트명은 즉시 resolve.
                const fontsLink = document.getElementById('scene-renderer-editor-fonts');
                const cssReady = fontsLink?._loadPromise || Promise.resolve(true);
                waits.push(cssReady.then(() =>
                    Promise.all([...fontSpecs].map(s => document.fonts.load(s).catch(() => null)))
                ));
            }
        }
        if (!waits.length) return Promise.resolve();
        console.info('[SceneRenderer] reveal gated on render resources', { waits: waits.length, sceneId: this._contract?.sceneId });
        return new Promise(resolve => {
            const timer = setTimeout(() => {
                console.warn('[SceneRenderer] render resources not ready in ' + RENDER_RESOURCE_TIMEOUT_MS + 'ms — revealing anyway', { sceneId: this._contract?.sceneId });
                resolve();
            }, RENDER_RESOURCE_TIMEOUT_MS);
            Promise.all(waits).then(() => { clearTimeout(timer); resolve(); });
        });
    }

    hide() {
        if (!this._el || this._hideTimer) return this;
        this._rootEl.classList.remove('visible');
        const dur = this._contract?.transitionDuration || 300;
        this._hideTimer = setTimeout(() => {
            this._hideTimer = null;
            this._finalizeHide();
        }, dur);
        return this;
    }

    /** hide 전환 종료 시 DOM 제거·바인딩 초기화. show()/reload() 가 대기 중 hide 를 즉시 마감할 때도 공유. */
    _finalizeHide() {
        this._unmountFit();
        this._el = null;
        this._rootEl = null;
        this._boundElements = {};
        this._groupWrappers = {};
        this._widgets = {};
    }

    /**
     * 이벤트 핸들러를 유지하면서 비주얼(계약 JSON)만 교체 — Hot Reload.
     * url은 fetch URL 문자열 또는 파싱된 계약 객체.
     */
    async reload(contractOrUrl) {
        if (this._hideTimer) {
            // hide 전환 대기 중이면 옛 DOM을 지금 마감 — 대기 타이머가 reload 산출 DOM을 지우는 레이스 방지.
            clearTimeout(this._hideTimer);
            this._hideTimer = null;
            this._finalizeHide();
        }
        const wasVisible = !!this._el;
        if (typeof contractOrUrl === 'string') await this.load(contractOrUrl);
        else this._contract = contractOrUrl;
        if (wasVisible) {
            this._unmountFit();
            if (this._styleEl?.parentNode) this._styleEl.parentNode.removeChild(this._styleEl);
            this._el = null;
            this._rootEl = null;
            this._styleEl = null;
            this._boundElements = {};
            this._groupWrappers = {};
            this._widgets = {};
            this._buildDOM();
            this._mountFit();
            this._rootEl.classList.add('visible');
            this._rootEl.style.opacity = '1';
            if (this._introAnimations) this._runSceneAnimations();
        }
        return this;
    }

    // ── Tab Navigation (navigation sceneType 전용) ────────────────────────────

    switchTab(tabId) {
        const c = this._contract;
        if (c?.sceneType !== 'navigation') {
            console.warn('[SceneRenderer] switchTab called on non-navigation scene; ignored.');
            return;
        }
        if (tabId === this._activeTab) return;

        const tabs = c.tabs || [];
        const tabOrder = tabs.map(t => t.id);
        const prevIdx = tabOrder.indexOf(this._activeTab);
        const nextIdx = tabOrder.indexOf(tabId);
        if (nextIdx < 0) {
            console.warn('[SceneRenderer] switchTab: unknown tabId', tabId);
            return;
        }
        const goRight = nextIdx > prevIdx;
        const tab = tabs[nextIdx];
        // 매칭 씬이 (none) 인 탭은 전환 대상이 아님 — 클릭/스와이프 무반응
        if (!tab.sceneName) {
            console.warn('[SceneRenderer] switchTab: tab has no matched scene; ignored.', tabId);
            return;
        }
        const transitionType = c.transitionType || 'slide';
        const dur = c.transitionDuration || 300;

        // nav 버튼 active 상태 갱신 (자유 배치 nav 버튼 레이어)
        this._el?.querySelectorAll('[data-nav-tab]').forEach(b => {
            b.classList.toggle('active', b.dataset.navTab === tabId);
        });
        // 동적 탭바 — 확장/아이콘/인디케이터 애니메이션을 콘텐츠 전환과 동시에 재생
        if (this._navTabBarCtl) this._navTabBarCtl.setActive(tabId);

        // 전경 스코프 오브젝트: 다음 탭에 속한 것만 렌더해 콘텐츠와 함께 슬라이드.
        if (this._navFgHostEl) {
            const fgHost = this._navFgHostEl;
            const prevFg = this._navFgInner;
            const nextFg = document.createElement('div');
            nextFg.className = 'sr-nav-fg-inner';
            nextFg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:hidden;pointer-events:none;';
            (this._navScopedLayers || []).forEach(l => {
                if (l.visible === false) return;
                if (!(l.tabIds || []).includes(tabId)) return;
                const layerEl = this._buildLayerEl(l); // x,y 는 _buildLayerEl 에서 viewport 절대좌표로 설정됨
                layerEl.style.pointerEvents = 'auto';
                nextFg.appendChild(layerEl);
            });
            fgHost.appendChild(nextFg);
            this._applyTabSlide(nextFg, prevFg, goRight, transitionType, dur);
            setTimeout(() => { if (prevFg && prevFg.parentNode) prevFg.parentNode.removeChild(prevFg); }, dur + 50);
            this._navFgInner = nextFg;
        }

        // 매칭 씬 contract 를 가져와 host 안에 새 SceneRenderer 인스턴스로 마운트
        const mountMatched = (matchedContract) => {
            if (!this._navHostEl) return;
            const host = this._navHostEl;
            const prevInner = this._navHostInner;
            const nextInner = document.createElement('div');
            nextInner.className = 'sr-nav-host-inner';
            nextInner.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:hidden;';
            host.appendChild(nextInner);

            // 새 SceneRenderer 마운트
            let mountedRenderer = null; // 이번 탭에 실제 마운트된 sub-renderer (실패/미매칭이면 null)
            if (matchedContract) {
                try {
                    const subRenderer = new SceneRenderer(nextInner, {
                        basePath: this._basePath,
                        safeArea: this._computeNavSafeArea(),
                        introAnimations: this._introAnimations,
                        wiringAudit: this._wiringAudit, // 에디터 플레이뷰(false)가 탭 씬까지 전파되도록
                    });
                    subRenderer.loadSync(matchedContract).show();
                    this._navHostRenderer = subRenderer;
                    mountedRenderer = subRenderer;
                } catch (e) {
                    console.error('[SceneRenderer] matched scene mount failed:', e);
                    nextInner.textContent = '[scene load error: ' + (tab.sceneName || tabId) + ']';
                }
            } else {
                nextInner.style.cssText += 'display:flex;align-items:center;justify-content:center;color:#888;font-family:monospace;font-size:12px;';
                nextInner.textContent = '(no matched scene: ' + (tab.sceneName || '') + ' — 미publish 이거나 scenes-index.json 에 없음)';
            }

            // 트랜지션 적용 (전경 슬라이드와 동일 헬퍼 — 동기화 보장)
            this._applyTabSlide(nextInner, prevInner, goRight, transitionType, dur);

            // 트랜지션 종료 후 prev 제거
            setTimeout(() => {
                if (prevInner && prevInner.parentNode) prevInner.parentNode.removeChild(prevInner);
            }, dur + 50);

            this._navHostInner = nextInner;
            this._activeTab = tabId;

            // 탭 마운트 통지 — 게임 코드는 이 이벤트로 sub-renderer 의 이벤트/바인딩을 재연결한다.
            // 최초 진입(show() 내 switchTab(defaultTabId))도 발생하므로 show() 전에 구독해 둘 것.
            this._emit('nav:tabchange', { tabId, sceneName: tab.sceneName || null, renderer: mountedRenderer });
        };

        const matched = (this._sceneRegistry && tab.sceneName) ? this._sceneRegistry[tab.sceneName] : null;
        if (matched) {
            mountMatched(matched);
        } else if (this._sceneFetch && tab.sceneName) {
            Promise.resolve(this._sceneFetch(tab.sceneName))
                .then(c2 => mountMatched(c2))
                .catch(err => { console.error('[SceneRenderer] sceneFetch failed:', err); mountMatched(null); });
        } else if (tab.sceneName && MODULE_BASE) {
            // 옵션 미주입 폴백 — publish 산출물 scenes-index.json 으로 이름→contract 자동 해석
            this._defaultSceneFetch(tab.sceneName)
                .then(c2 => mountMatched(c2))
                .catch(err => {
                    console.error('[SceneRenderer] 탭 씬 기본 해석 실패(' + tab.sceneName + ') — sceneFetch/sceneRegistry 옵션 주입을 권장:', err);
                    mountMatched(null);
                });
        } else {
            mountMatched(null);
        }
    }

    /**
     * 탭 전환 슬라이드/페이드 트랜지션을 적용. 콘텐츠 inner 와 전경 스코프 inner 가
     * 동일하게 움직이도록 양쪽에서 공유하는 단일 헬퍼.
     * @param {HTMLElement} nextEl 들어오는 inner
     * @param {HTMLElement|null} prevEl 나가는 inner (없으면 최초 진입)
     * @param {boolean} goRight 다음 탭이 오른쪽이면 true
     * @param {string} type 'fade' | 'slide'
     * @param {number} dur ms
     */
    _applyTabSlide(nextEl, prevEl, goRight, type, dur) {
        // 인트로 억제 모드의 최초 마운트(prevEl 없음)는 전환 없이 즉시 표시 — 사용자가 탭을 눌러
        // 전환할 때(prevEl 있음)는 억제 모드에서도 슬라이드/페이드가 정상 재생된다.
        if (!prevEl && !this._introAnimations) return;
        if (type === 'fade') {
            nextEl.style.opacity = '0';
            nextEl.style.transition = `opacity ${dur}ms ease`;
            requestAnimationFrame(() => requestAnimationFrame(() => {
                nextEl.style.opacity = '1';
                if (prevEl) {
                    prevEl.style.transition = `opacity ${dur}ms ease`;
                    prevEl.style.opacity = '0';
                }
            }));
        } else {
            nextEl.style.transition = 'none';
            nextEl.style.transform = goRight ? 'translateX(100%)' : 'translateX(-100%)';
            requestAnimationFrame(() => requestAnimationFrame(() => {
                nextEl.style.transition = `transform ${dur}ms ease`;
                nextEl.style.transform = 'translateX(0)';
                if (prevEl) {
                    prevEl.style.transition = `transform ${dur}ms ease`;
                    prevEl.style.transform = goRight ? 'translateX(-100%)' : 'translateX(100%)';
                }
            }));
        }
    }

    // ── Event System ──────────────────────────────────────────────────────────

    /**
     * 계약에서 선언된 이벤트를 구독.
     * 반환값은 구독 해제 함수: const off = renderer.on('...', fn); off();
     */
    on(eventName, handler) {
        if (!this._handlers[eventName]) this._handlers[eventName] = new Set();
        this._handlers[eventName].add(handler);
        return () => this._handlers[eventName]?.delete(handler);
    }

    off(eventName, handler) {
        this._handlers[eventName]?.delete(handler);
    }

    _emit(eventName, payload) {
        this._handlers[eventName]?.forEach(h => h(payload));
    }

    // ── Data Binding ──────────────────────────────────────────────────────────

    /**
     * 데이터 바인딩 업데이트. 변경된 노드만 DOM 업데이트.
     * renderer.update({ player: { coins: 500, name: '홍길동' } })
     */
    update(data) {
        const flat = this._flattenPaths(data);
        for (const [key, value] of Object.entries(flat)) {
            this._dataValues[key] = value; // 버퍼에 누적 → 이후 _buildDOM이 첫 페인트부터 시드
            (this._boundElements[key] || []).forEach(el => this._applyBoundText(el, value));
            (this._boundImages[key] || []).forEach(img => this._applyBoundImage(img, value));
            (this._widgets[key] || []).forEach(w => this._applyWidget(w, value));
        }
        return this;
    }

    /** 바인딩 텍스트 1개의 표시값 적용 (공통). template({value} 치환) 우선, 없으면 raw. */
    _applyBoundText(span, value) {
        const tpl = span.dataset.bindingTemplate;
        span.textContent = tpl ? tpl.replaceAll('{value}', String(value)) : String(value);
        // 그라데이션 오버레이(::after content:attr)와 글자 내용 동기화
        if (span.dataset.gradText !== undefined) span.dataset.gradText = span.textContent;
    }

    /** 바인딩 이미지 1개의 src 적용 (공통). 9-slice 이미지는 div+border-image 로 렌더되므로 소스도 border-image 로 교체. */
    _applyBoundImage(img, value) {
        const src = this._resolveAssetPath(String(value));
        if (img.tagName === 'IMG') img.src = src;
        else img.style.borderImageSource = `url('${src}')`;
    }

    /** 표시 적용 1개 (위젯 visibility/toggle 공용). truthy=표시, falsy=숨김. 문자열화된 'false'/'0' 은 게임 코드의 String() 실수 대비로 숨김 취급. */
    _applyBoundVisibility(el, value) {
        const visible = (value === 'false' || value === '0') ? false : !!value;
        el.style.display = visible ? '' : 'none';
    }

    // ── 위젯 (표시/토글/슬라이더) ─────────────────────────────────────────────
    // 선언 위치: contract group.widget 또는 layer.widget = { type, key, ...슬롯 }
    //   visibility — 슬롯 없음, 호스트 자신(그룹 멤버들/오브젝트)을 boolean 으로 표시/숨김
    //   toggle    — on/off ref, boolean 으로 두 참조를 반대로 표시 스왑
    //   slider    — track/handle(/fill) ref, 0~1 값으로 핸들 이동·채우기 클립
    //   fill      — fill ref(/bg), 0~100 값으로 채우기 클립(로딩바). 표시 전용, 입력 배선 없음
    // ref = { kind:'group'|'layer', id } — group=contract 그룹 id, layer=stableId.
    // 입력: 토글 클릭·슬라이더 드래그는 'widget:<key>' 이벤트({key,type,value,phase})로만 방출하고
    //   스스로 시각 상태를 바꾸지 않는다. 상태의 진실은 게임 — update({key:값}) 에코로만 UI가 움직인다.
    // 첫 update() 전에는 디자인 시점 상태 그대로 노출된다.
    _initWidgets(c, root) {
        this._widgets = {};
        const groupById = {};
        (c.groups || []).forEach(g => { if (g.id) groupById[g.id] = g; });
        const refSids = (ref) => !ref?.id ? []
            : (ref.kind === 'group' ? (groupById[ref.id]?.layerStableIds || []) : [ref.id]);
        // 그룹 ref 는 그룹 래퍼가 아닌 멤버 wrap 개별 제어 — fx번들 소속 멤버는 그룹 래퍼 밖에 살기 때문
        const refEls = (ref) => refSids(ref)
            .map(sid => root.querySelector(`[data-stable-id="${sid}"]`))
            .filter(Boolean);
        // ref 의 디자인 시점 합집합 bounds (그룹=멤버 union) — 슬라이더 트랙 범위·핸들 기준점
        const refBounds = (ref) => {
            const sids = new Set(refSids(ref));
            let nX = Infinity, nY = Infinity, xX = -Infinity, xY = -Infinity;
            (c.layers || []).forEach(l => {
                if (!sids.has(l.stableId)) return;
                const b = contractLayerBounds(l);
                nX = Math.min(nX, b.x); nY = Math.min(nY, b.y);
                xX = Math.max(xX, b.x + b.w); xY = Math.max(xY, b.y + b.h);
            });
            return (isFinite(nX) && xX > nX) ? { x: nX, y: nY, w: xX - nX, h: xY - nY } : null;
        };
        // 입력 배선 — 토글: 클릭 → 다음 값 제안을 이벤트로만 방출. 시각 변화는 게임 update() 에코 몫.
        const wireToggle = (inst, key) => {
            [...inst.onEls, ...inst.offEls].forEach(el => {
                el.style.cursor = 'pointer';
                el.style.pointerEvents = 'auto';
                el.addEventListener('click', () => {
                    const cur = this._dataValues[key];
                    const on = (cur === 'false' || cur === '0') ? false : !!cur;
                    this._emit('widget:' + key, { key, type: 'toggle', value: !on, phase: 'change' });
                });
            });
        };
        // 입력 배선 — 슬라이더: 트랙/핸들 pointerdown 후 드래그. 이동 중 phase:'input', 놓으면 'change'.
        const wireSlider = (inst, key) => {
            const toValue = (ev) => {
                // scale-with-screen(_mountFit)·스크롤 보정: 화면px → 디자인px 는 rect 대비 layout 크기 비율로 환산
                const rect = root.getBoundingClientRect();
                const sx = rect.width / (root.offsetWidth || 1) || 1;
                const sy = rect.height / (root.offsetHeight || 1) || 1;
                const v = inst.vertical
                    ? (inst.track.y + inst.track.h - (ev.clientY - rect.top) / sy) / inst.track.h
                    : ((ev.clientX - rect.left) / sx - inst.track.x) / inst.track.w;
                return Math.max(0, Math.min(1, v));
            };
            const start = (downEv) => {
                downEv.preventDefault();
                const move = (mv) => this._emit('widget:' + key, { key, type: 'slider', value: toValue(mv), phase: 'input' });
                const up = (uv) => {
                    window.removeEventListener('pointermove', move);
                    window.removeEventListener('pointerup', up);
                    this._emit('widget:' + key, { key, type: 'slider', value: toValue(uv), phase: 'change' });
                };
                window.addEventListener('pointermove', move);
                window.addEventListener('pointerup', up);
                move(downEv); // 누른 지점 값으로 즉시 input 1회 (트랙 클릭 점프)
            };
            [...inst.trackEls, ...inst.handleEls].forEach(el => {
                el.style.cursor = 'pointer';
                el.style.pointerEvents = 'auto';
                el.style.touchAction = 'none'; // 드래그 중 페이지 스크롤 개입 방지
                el.addEventListener('pointerdown', start);
            });
        };
        // 호스트 = 그룹(self ref=그룹 id) + 레이어(self ref=stableId) — visibility 는 self 를 대상으로 한다
        const hosts = [];
        (c.groups || []).forEach(g => { if (g.widget) hosts.push({ wg: g.widget, self: { kind: 'group', id: g.id } }); });
        (c.layers || []).forEach(l => { if (l.widget) hosts.push({ wg: l.widget, self: { kind: 'layer', id: l.stableId } }); });
        hosts.forEach(({ wg, self }) => {
            if (!wg.key || !wg.type) return;
            let inst = null;
            if (wg.type === 'visibility') {
                const els = refEls(self);
                if (els.length) inst = { type: 'visibility', els };
            } else if (wg.type === 'toggle') {
                const onEls = refEls(wg.on), offEls = refEls(wg.off);
                if (onEls.length || offEls.length) inst = { type: 'toggle', onEls, offEls };
            } else if (wg.type === 'fill') {
                const fb = refBounds(wg.fill), fillEls = refEls(wg.fill);
                if (fb && fillEls.length) inst = { type: 'fill', vertical: fb.h > fb.w, fillEls };
            } else if (wg.type === 'slider') {
                const track = refBounds(wg.track);
                const handle = refBounds(wg.handle);
                const handleEls = refEls(wg.handle);
                if (track && handle && handleEls.length) {
                    inst = { type: 'slider', vertical: track.h > track.w, track, handle, handleEls, trackEls: refEls(wg.track), fillEls: refEls(wg.fill) };
                }
            }
            if (!inst) return;
            if (!this._widgets[wg.key]) this._widgets[wg.key] = [];
            this._widgets[wg.key].push(inst);
            // show() 이전에 도착한 update() 값 시드 — 첫 페인트부터 실제 상태
            if (Object.prototype.hasOwnProperty.call(this._dataValues, wg.key)) {
                this._applyWidget(inst, this._dataValues[wg.key]);
            }
            // 2단계 입력 — visibility 는 표시 전용이라 배선 없음
            if (inst.type === 'toggle') wireToggle(inst, wg.key);
            else if (inst.type === 'slider') wireSlider(inst, wg.key);
        });
    }

    /** 위젯 1개에 update() 값 적용. visibility=표시/숨김, 토글=on/off 스왑, 슬라이더=핸들 translate + 채우기 clip.
     *  슬라이더 채우기는 "가득 찬 상태"로 그려둔 오브젝트를 진행률만큼 잘라 보여준다(도형 왜곡 없음). */
    _applyWidget(w, value) {
        if (w.type === 'visibility') {
            w.els.forEach(el => this._applyBoundVisibility(el, value));
            return;
        }
        if (w.type === 'toggle') {
            const on = (value === 'false' || value === '0') ? false : !!value;
            w.onEls.forEach(el => this._applyBoundVisibility(el, on));
            w.offEls.forEach(el => this._applyBoundVisibility(el, !on));
            return;
        }
        // fill — 0~100 을 진행률로 클램프해 "가득 찬 상태" 오브젝트를 잘라 보여준다 (입력 배선 없음, 표시 전용)
        if (w.type === 'fill') {
            const v = Math.max(0, Math.min(1, (parseFloat(value) || 0) / 100));
            w.fillEls.forEach(el => {
                el.style.clipPath = w.vertical ? `inset(${(1 - v) * 100}% 0 0 0)` : `inset(0 ${(1 - v) * 100}% 0 0)`;
            });
            return;
        }
        // slider — 0~1 클램프. 가로=좌→우 증가, 세로=아래→위 증가. 핸들 중심이 트랙 범위를 따라간다.
        const v = Math.max(0, Math.min(1, parseFloat(value) || 0));
        if (w.vertical) {
            const d = (w.track.y + w.track.h - v * w.track.h) - (w.handle.y + w.handle.h / 2);
            w.handleEls.forEach(el => { el.style.transform = `translateY(${d}px)`; });
            w.fillEls.forEach(el => { el.style.clipPath = `inset(${(1 - v) * 100}% 0 0 0)`; });
        } else {
            const d = (w.track.x + v * w.track.w) - (w.handle.x + w.handle.w / 2);
            w.handleEls.forEach(el => { el.style.transform = `translateX(${d}px)`; });
            w.fillEls.forEach(el => { el.style.clipPath = `inset(0 ${(1 - v) * 100}% 0 0)`; });
        }
    }

    /** stableId로 DOM 요소에 직접 접근 (고급 사용). */
    getElement(stableId) {
        return this._el?.querySelector(`[data-stable-id="${stableId}"]`) ?? null;
    }

    /** 그룹 이름으로 래퍼 div에 접근. show/hide/transform 등 그룹 전체 제어에 사용. */
    getGroup(name) {
        return this._groupWrappers[name] ?? null;
    }

    /** 레이어 표시 이름(displayName)으로 DOM 요소에 접근. 동일 이름이 여럿이면 첫 번째. (GameSession의 'GameField' 마운트 지점 해석에 사용) */
    getElementByName(name) {
        const layer = (this._contract?.layers || []).find(l => l.displayName === name);
        return layer ? this.getElement(layer.stableId) : null;
    }

    /** stableId의 특정 텍스트 슬롯 span 요소에 접근. */
    getTextElement(stableId, slotIndex = 0) {
        return this.getElement(stableId)?.querySelector(`.text-${slotIndex}`) ?? null;
    }

    /** 스프라이트 레이어의 재생속도를 런타임에 실시간 변경(1=기본, 0=일시정지, 0.5=절반속도, 2=배속). */
    setSpriteRate(stableId, rate) {
        const cv = this.getElement(stableId)?.querySelector('canvas');
        if (cv) cv._spriteRate = rate;
        return this;
    }

    /**
     * scene-flow.json 엣지의 transitionOut/transitionIn 스펙을 이 씬 위에 재생.
     * 게임 코드의 씬 전환 절차: from.playTransition(edge.transitionOut) → await → from.hide()
     * → to.show() → to.playTransition(edge.transitionIn).
     * spec: { type:'screen-transition', color, fromOpacity, toOpacity, durationMs }
     *     | { type:'image-curtain', gatherMs, holdMs, scatterMs, curtainLayers, curtainAutoAll }
     * 재생 종료 시점에 resolve 되는 Promise 반환 (spec 이 없으면 즉시 resolve — 분기 없이 await 가능).
     */
    playTransition(spec) {
        if (!spec || !this._el) return Promise.resolve();
        if (spec.type === 'image-curtain') {
            const total = Math.max(0, spec.gatherMs ?? 500) + Math.max(0, spec.holdMs ?? 0) + Math.max(0, spec.scatterMs ?? 500);
            const maxDelay = (Array.isArray(spec.curtainLayers) ? spec.curtainLayers : []).reduce((m, l) => Math.max(m, l.curtainDelayMs || 0), 0);
            this._runImageCurtain(spec, 0);
            return new Promise(res => setTimeout(res, maxDelay + total + 80));
        }
        if (spec.type === 'screen-transition') {
            const duration = Math.max(0, spec.durationMs ?? 500);
            this._runScreenTransition(spec, 0, duration);
            return new Promise(res => setTimeout(res, duration));
        }
        console.warn('[SceneRenderer] playTransition: 알 수 없는 전환 타입', spec);
        return Promise.resolve();
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    /** 타임라인 항목들의 시작·길이 스케줄 계산 — _runSceneAnimations(재생)와 _timelineEmitDeferMs(총 길이)가 공유. */
    _scheduleSceneAnimations(items) {
        let cursor = 0;
        let previousStart = 0;
        const scheduled = [];
        items.forEach((item, index) => {
            if (item.enabled === false) return;
            const mode = item.startMode || 'afterPrevious';
            const base = mode === 'withPrevious' ? previousStart : mode === 'atTime' ? (item.startTimeMs || 0) : cursor;
            const start = Math.max(0, base + (item.delayMs || 0));
            const duration = Math.max(0, item.durationMs || 0);
            cursor = Math.max(cursor, start + duration);
            previousStart = start;
            scheduled.push({ item, index, start, duration });
        });
        return scheduled;
    }

    /**
     * 클릭 트리거 타임라인 대상(또는 같은 그룹 멤버)의 흐름 이벤트 발화 지연량(ms). 해당 없으면 0.
     * 개봉 연출처럼 "클릭 → 연출 재생 → 끝나면 자동 전환"인 씬에서, 같은 클릭에 걸린 흐름 이벤트가
     * 연출을 끊고 즉시 전환하지 않도록 타임라인 총 길이만큼 지연 발화한다(연출 소비 후 클릭은 즉시).
     */
    _timelineEmitDeferMs(stableId) {
        const trig = this._contract?.sceneAnimationsTrigger;
        const items = this._contract?.sceneAnimations;
        if (trig?.type !== 'click' || !Array.isArray(items) || !items.length) return 0;
        if (this._timelineClickRan) return 0;
        if (stableId !== trig.targetStableId) {
            const grouped = (this._contract.groups || []).some(g => {
                const ids = g.layerStableIds || [];
                return ids.includes(trig.targetStableId) && ids.includes(stableId);
            });
            if (!grouped) return 0;
        }
        return this._scheduleSceneAnimations(items).reduce((end, s) => Math.max(end, s.start + s.duration), 0);
    }

    _runSceneAnimations() {
        const items = this._contract?.sceneAnimations;
        if (!Array.isArray(items) || !items.length || !this._el) return;

        // 터치 트리거 — 씬 표시 시점 대신 대상 레이어 클릭에서 1회 재생(표시마다 재무장).
        // 개봉 연출(닫힌 상자 터치 → 점프 중 이미지 교체 → 광채) 같은 유저 입력 기점 타임라인용.
        const trig = this._contract.sceneAnimationsTrigger;
        if (trig?.type === 'click' && !this._timelineClickWired) {
            const target = this.getElement(trig.targetStableId);
            if (!target) {
                console.warn('[SceneRenderer] 타임라인 터치 트리거 대상 레이어 없음:', trig.targetStableId);
                return;
            }
            this._timelineClickWired = true;
            target.style.cursor = 'pointer';
            target.addEventListener('click', () => this._runSceneAnimations(), { once: true });
            return;
        }
        if (trig?.type === 'click') this._timelineClickRan = true; // 소비됨 — 이후 클릭 이벤트는 즉시 발화

        const scheduled = this._scheduleSceneAnimations(items);
        console.info('[SceneRenderer] scene animation schedule', scheduled.map(({ item, index, start, duration }) => ({
            index,
            type: item.type,
            presetId: item.cssPresetId || item.presetId,
            targetStableId: item.targetStableId || '',
            curtainLayers: Array.isArray(item.curtainLayers) ? item.curtainLayers.length : undefined,
            start,
            duration,
        })));

        scheduled.forEach(({ item, start, duration }) => {
            if (item.type !== 'object-animation' || !item.targetStableId) return;
            const target = this.getElement(item.targetStableId);
            if (!target) return;
            [target, ...target.querySelectorAll('*')].forEach(el => {
                if (el._uiCssAnimationClasses || el._uiCssAnimationEndHandler || el._uiCssAnimationLoopTimer) {
                    applyCssAnimationEffect(el, { enabled: false });
                }
            });
            const presetId = item.cssPresetId || item.presetId || 'fade-in';
            const effect = normalizeCssAnimationEffect({
                cssAnimation: {
                    enabled: true,
                    presetId,
                    duration: Math.max(0.001, duration / 1000),
                    delay: 0,
                    repeat: 1,
                    loop: !!item.loop,
                    loopDelay: 0, // 타임라인 loop 는 즉시 재시작(점멸 연속성) — 휴식은 duration 으로 조절
                },
            });
            if (effect.params?.phase === 'enter') {
                target.style.visibility = 'hidden';
            }
        });

        scheduled.forEach(({ item, start, duration }) => {
            if (item.type === 'image-curtain') {
                this._runImageCurtain(item, start);
                return;
            }
            if (item.type === 'screen-transition') {
                this._runScreenTransition(item, start, duration);
                return;
            }

            // 이미지 교체 타임라인 항목: 시작 시점에 대상 image 레이어의 그림을 소스 레이어의 그림으로
            // 교체한다. 같은 엘리먼트에서 src 만 바꿔야 진행 중인 css 애니메이션 모션이 끊기지 않는다
            // (개봉 연출: 점프 도중 닫힌 상자 → 열린 상자).
            if (item.type === 'image-swap' && item.targetStableId) {
                const target = this.getElement(item.targetStableId);
                const srcLayer = (this._contract.layers || []).find(l => l.stableId === item.sourceStableId);
                const srcPath = srcLayer?.image?.exportPath || srcLayer?.visual?.exportPath || '';
                if (!target || !srcPath) {
                    console.warn('[SceneRenderer] image-swap 대상/소스 미해석:', item.targetStableId, '→', item.sourceStableId);
                    return;
                }
                const src = this._resolveAssetPath(srcPath);
                setTimeout(() => {
                    if (!target.isConnected) return;
                    const img = target.querySelector('img');
                    if (!img) {
                        console.warn('[SceneRenderer] image-swap: 대상에 <img> 가 없습니다(image 레이어만 지원):', item.targetStableId);
                        return;
                    }
                    img.src = src;
                }, start);
                return;
            }
            // Sparkle(파티클) 타임라인 항목: 시작 시점에 1회 재생. ambient-aura(반복형)는
            // duration 동안만 유지 후 제거(0이면 계속) — 타임라인 시점 제어 의미 유지.
            if (item.type === 'particle-effect' && item.targetStableId) {
                const target = this.getElement(item.targetStableId);
                if (!target) {
                    console.warn('[SceneRenderer] scene animation target not found:', item.targetStableId, item);
                    return;
                }
                const effect = normalizeParticleEffect({ particleEffect: { enabled: true, presetId: item.particlePresetId || '' } });
                setTimeout(() => {
                    if (!target.isConnected) return;
                    // 부착 영역(대상 박스 기준 %): boxX/Y = 영역의 "밑변 중심"(기준점), boxW/H = 이펙트 크기.
                    // % 단위라 대상 오브젝트를 리사이즈해도 위치·크기가 비율로 따라간다.
                    // 기준점이 밑변 중심이라 W/H 를 바꿔도 발밑(상자 입구선)이 고정된 채 크기만 변한다.
                    // 내부형(treasure-glow 등)은 auraWidth/Height 도 영역의 실측 px 로 맞춘다 — 영역이 곧 이펙트 크기.
                    // (미지정 시 대상 전체 박스 = 기존 동작.)
                    let host = target;
                    const ov = {}; // 항목별 파라미터 노브(0/미지정 = 프리셋 값)
                    if (item.fxCount > 0) ov.count = item.fxCount;
                    if (item.fxSpread > 0) ov.spread = item.fxSpread;
                    if (item.boxW > 0 || item.boxH > 0) {
                        const w = item.boxW || 0, h = item.boxH || 0;
                        host = document.createElement('div');
                        host.style.cssText = `position:absolute;left:${(item.boxX || 0) - w / 2}%;top:${(item.boxY || 0) - h}%;width:${w}%;height:${h}%;pointer-events:none;`;
                        target.appendChild(host);
                        if (w) ov.auraWidth = host.offsetWidth;
                        if (h) ov.auraHeight = host.offsetHeight;
                    }
                    if (Object.keys(ov).length) effect.params = { ...effect.params, ...ov };
                    playParticleEffect(host, effect);
                    // 내부 반복형(ambient/healing)은 컨테이너 클래스를 공유하므로 제거 경로도 하나로 통한다
                    if (effect.source?.provider === 'internal' && duration > 0) {
                        setTimeout(() => applyAmbientSparkleAura(host, { enabled: false }), duration);
                    }
                }, start);
                return;
            }
            // Spin 타임라인 항목: 시작 시점부터 duration 동안 회전 후 정지(duration 0 = 무한).
            // spinPeriodMs = 1회전 시간. 오브젝트 상시 spin(_applyComponentVisual)과 별개 축.
            if (item.type === 'spin' && item.targetStableId) {
                const target = this.getElement(item.targetStableId);
                if (!target) {
                    console.warn('[SceneRenderer] scene animation target not found:', item.targetStableId, item);
                    return;
                }
                setTimeout(() => {
                    if (!target.isConnected) return;
                    ensureSpinKeyframes();
                    const periodMs = Math.max(100, item.spinPeriodMs || 2000);
                    const name = item.spinDirection === 'ccw' ? 'ui-spin-rev' : 'ui-spin';
                    target.style.animation = `${name} ${periodMs}ms linear infinite`;
                    target.style.transformOrigin = '50% 50%';
                    if (duration > 0) {
                        setTimeout(() => { if (target.isConnected) target.style.animation = ''; }, duration);
                    }
                }, start);
                return;
            }

            if (item.type !== 'object-animation' || !item.targetStableId) return;
            const target = this.getElement(item.targetStableId);
            if (!target) {
                console.warn('[SceneRenderer] scene animation target not found:', item.targetStableId, item);
                return;
            }
            const presetId = item.cssPresetId || item.presetId || 'fade-in';
            const effect = normalizeCssAnimationEffect({
                cssAnimation: {
                    enabled: true,
                    presetId,
                    duration: Math.max(0.001, duration / 1000),
                    delay: 0,
                    repeat: 1,
                    loop: !!item.loop,
                    loopDelay: 0,
                },
            });
            setTimeout(() => {
                if (!target.isConnected) return;
                target.style.visibility = '';
                console.info('[SceneRenderer] apply scene css effect', {
                    targetStableId: item.targetStableId,
                    presetId,
                    start,
                    duration,
                });
                applyCssAnimationEffect(target, effect);
            }, start);
        });
    }

    /**
     * 색 오버레이 페이드(screen-transition) 재생 — 씬 타임라인(_runSceneAnimations)과
     * 흐름도 엣지 재생(playTransition)이 공유하는 단일 재생 경로.
     * toOpacity>0(덮은 채 종료)이면 오버레이가 남는다 — 게임이 hide()/씬 교체로 정리하는 전제(Out 효과).
     * @param {object} item { color, fromOpacity, toOpacity, easing? }
     * @param {number} start 시작 지연(ms)
     * @param {number} duration 재생 시간(ms)
     */
    _runScreenTransition(item, start, duration) {
        const overlay = document.createElement('div');
        overlay.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;z-index:99999;background:' + (item.color || '#000000') + ';opacity:' + (item.fromOpacity ?? 0) + ';';
        this._el.appendChild(overlay);
        if (typeof overlay.animate !== 'function') {
            overlay.style.opacity = item.toOpacity ?? 1;
            return;
        }
        const anim = overlay.animate(
            [{ opacity: item.fromOpacity ?? 0 }, { opacity: item.toOpacity ?? 1 }],
            { delay: start, duration, easing: item.easing || 'ease', fill: 'forwards' }
        );
        anim.finished.then(() => {
            if ((item.toOpacity ?? 1) <= 0 && overlay.parentNode) overlay.parentNode.removeChild(overlay);
        }).catch(() => {});
    }

    /**
     * 이미지 커튼(구름/나뭇잎) 화면전환. 자기완결형 한 항목으로
     * "모임(화살표 반대에서 날아와 덮음) → 유지 → 흩어짐(화살표 방향으로 빠져나감)"을 재생.
     * 커튼 오브젝트는 씬 레이어가 아니라 item.curtainLayers 에 따로 배치된 레이어 객체다(씬 미간섭) —
     * 각 레이어의 위치가 "덮는 위치", curtainAngleDeg 가 흩어질 방향(모임은 반대)이다.
     * 전용 overlay 에 _buildLayerEl 로 빌드해 얹고 translate/rotate 를 애니메이션한다.
     * @param {object} item image-curtain 항목 (curtainLayers:[레이어 객체], curtainAutoAll)
     * @param {number} start 스케줄 시작 시각(ms) — 각 target delayMs 는 여기에 더해짐
     */
    _runImageCurtain(item, start) {
        if (!this._el) return;
        const cls = Array.isArray(item.curtainLayers) ? item.curtainLayers : [];
        if (!cls.length) return;
        const boxW = this._designW || this._contract?.viewport?.width || this._contract?.canvas?.width || 390;
        const boxH = this._designH || this._contract?.viewport?.height || this._contract?.canvas?.height || 844;
        const gatherMs = Math.max(0, item.gatherMs ?? 500);
        const holdMs = Math.max(0, item.holdMs ?? 0);
        const scatterMs = Math.max(0, item.scatterMs ?? 500);
        const total = gatherMs + holdMs + scatterMs;
        if (total <= 0) return;

        // 커튼 오브젝트 전용 overlay(씬 위 z최상단). 커튼 레이어는 씬 레이어가 아니라
        // item.curtainLayers(별도 배치)이므로 기존 _buildLayerEl 로 빌드해 얹는다(씬 미간섭).
        const overlay = document.createElement('div');
        overlay.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:hidden;pointer-events:none;z-index:99999;';
        this._el.appendChild(overlay);

        cls.forEach((layer) => {
            const el = this._buildLayerEl(layer);   // 컴포넌트·회전·스케일·이미지 모두 지원(재사용)
            el.style.visibility = 'hidden';
            overlay.appendChild(el);

            const w = (layer.visual?.width || layer.visual?.model?.shape?.width || el.offsetWidth || 128) * (layer.scale || 1) * (layer.scaleX || 1);
            const h = (layer.visual?.height || layer.visual?.model?.shape?.height || el.offsetHeight || 128) * (layer.scale || 1) * (layer.scaleY || 1);
            const x = layer.x || 0, y = layer.y || 0;
            const spin = layer.curtainSpinDeg || 0;
            const delay = Math.max(0, layer.curtainDelayMs || 0);

            // 흩어질 방향: auto=뷰포트 중앙→오브젝트 중앙의 바깥 방향(방사형 탈출구). 아니면 지정 각도.
            // 일괄(item.curtainAutoAll)은 개별(layer.curtainAuto)보다 우선.
            let angleDeg = layer.curtainAngleDeg || 0;
            if (item.curtainAutoAll || layer.curtainAuto) {
                const cx = x + w / 2, cy = y + h / 2;      // 오브젝트 중앙
                const ddx = cx - boxW / 2, ddy = cy - boxH / 2;   // 뷰포트 중앙 → 오브젝트(바깥 방향)
                angleDeg = (ddx === 0 && ddy === 0) ? 90 : Math.atan2(ddy, ddx) * 180 / Math.PI;
            }
            const rad = angleDeg * Math.PI / 180;
            const dx = Math.cos(rad), dy = Math.sin(rad);
            // 레이어 박스가 그 방향으로 화면 밖으로 완전히 벗어나는 최소 거리(+여유 5%).
            const distX = dx > 0 ? (boxW - x) / dx : dx < 0 ? (x + w) / -dx : Infinity;
            const distY = dy > 0 ? (boxH - y) / dy : dy < 0 ? (y + h) / -dy : Infinity;
            const dist = (Math.min(distX, distY) * 1.05) + 4;
            // 왕복: 화살표(탈출) 방향 쪽 화면 밖을 "집"으로 삼는다.
            //   집(화살표쪽 밖) → 덮음(제자리) → 다시 집(화살표쪽 밖)으로 되돌아 나감.
            //   진입=화살표 반대방향 이동(집→중앙), 이탈=화살표 방향 이동(중앙→집).
            const homeX = dx * dist, homeY = dy * dist;

            // translate/rotate 독립 속성 → _buildLayerEl 의 transform(회전·스케일) 보존.
            el.style.translate = `${homeX}px ${homeY}px`;
            el.style.rotate = `${spin}deg`;

            setTimeout(() => {
                if (!el.isConnected) return;
                el.style.visibility = '';
                if (typeof el.animate !== 'function') { el.style.translate = '0px 0px'; el.style.rotate = '0deg'; return; }
                el.animate([
                    { offset: 0, translate: `${homeX}px ${homeY}px`, rotate: `${spin}deg`, easing: 'ease-out' },
                    { offset: gatherMs / total, translate: '0px 0px', rotate: '0deg', easing: 'linear' },
                    { offset: (gatherMs + holdMs) / total, translate: '0px 0px', rotate: '0deg', easing: 'ease-in' },
                    { offset: 1, translate: `${homeX}px ${homeY}px`, rotate: `${spin}deg` },
                ], { duration: total, fill: 'both' });
            }, start + delay);
        });

        const maxDelay = cls.reduce((m, l) => Math.max(m, l.curtainDelayMs || 0), 0);
        setTimeout(() => { if (overlay.parentNode) overlay.parentNode.removeChild(overlay); }, start + maxDelay + total + 80);
    }

    _buildDOM() {
        const c = this._contract;
        this._groupWrappers = {};
        this._timelineClickWired = false; // 터치 트리거 타임라인 — DOM 재구축마다 재무장
        this._timelineClickRan = false;   // 지연 발화 판정도 재무장 (_timelineEmitDeferMs)
        this._timelinePendingEmits?.clear();

        // ── Navigation Scene 모드 ────────────────────────────────────────────
        if (c.sceneType === 'navigation') {
            return this._buildNavigationDOM();
        }

        // ── 일반 Scene 모드 ─────────────────────────────────────────────────
        const w = c.canvas.width; const h = c.canvas.height;
        const vw = c.viewport ? c.viewport.width : w;
        const vh = c.viewport ? c.viewport.height : h;

        // safeArea: navigation host 가 차지하는 공간(가려진 영역) — 스크롤 시 콘텐츠가 그 뒤로 숨지 않게 차감
        const sa = this._safeArea || { top:0, bottom:0, left:0, right:0 };
        const safeTop = sa.top || 0;
        const safeBottom = sa.bottom || 0;
        const effViewH = Math.max(0, vh - safeTop - safeBottom);

        // 스마트 스크롤: 콘텐츠 높이 계산 — 핀(scrollFixed) 그룹 멤버는 스크롤 밖에 살므로 높이에서 제외
        const pinnedSids = new Set((c.groups || []).flatMap(g => g.scrollFixed ? g.layerStableIds : []));
        let maxBottom = 0;
        (c.layers || []).forEach(l => {
            if (l.visible === false || l.scrollFixed || pinnedSids.has(l.stableId)) return;
            const baseH = l.visual?.height
                       || l.visual?.model?.shape?.height
                       || 0;
            const lh = baseH * (l.scale || 1) * (l.scaleY || 1);
            maxBottom = Math.max(maxBottom, (l.y || 0) + lh);
        });
        // 하단 여백: 마지막 오브젝트가 뷰포트/네비바에 딱 붙지 않게 숨 쉴 공간 확보
        const BOTTOM_PADDING = 60;
        const contentH = Math.max(maxBottom ? maxBottom + BOTTOM_PADDING : effViewH, effViewH);
        const isScrollable = contentH > effViewH;

        this._injectCSS(isScrollable);

        const root = document.createElement('div');
        root.id = c.sceneId;
        root.style.cssText = `position:relative;width:${w}px;height:${contentH}px;overflow:hidden;opacity:0;transition:opacity 0.3s ease;z-index:5;`;
        this._applyBackground(root, c.background);

        // 핀(스크롤 고정) 래퍼 모음 — 그룹 핀과 개별 오브젝트 핀이 같은 통로로 outerWrap 에 붙는다
        const pinnedGDivs = [];
        let loosePinDiv = null;
        const pinWrap = () => {
            if (!loosePinDiv) {
                loosePinDiv = document.createElement('div');
                loosePinDiv.style.cssText = `position:absolute;top:0;left:0;width:${w}px;height:${contentH}px;pointer-events:none;`;
                pinnedGDivs.push(loosePinDiv);
            }
            return loosePinDiv;
        };

        // 그룹 래퍼 생성 (편집/AI 단위 — getGroup show/hide 용. 효과는 아래 fx번들이 담당한다.)
        const layerGroupMap = {};
        const groupList = [];
        (c.groups || []).forEach((g, idx) => {
            const maxZ = c.layers.filter(l => g.layerStableIds.includes(l.stableId)).reduce((mx, l) => Math.max(mx, l.zIndex || 0), 0);
            const gDiv = document.createElement('div');
            gDiv.dataset.group = g.name;
            gDiv.style.cssText = `position:absolute;top:0;left:0;width:${w}px;height:${contentH}px;pointer-events:none;z-index:${maxZ};transform-origin:center center;`;
            if (g.name) this._groupWrappers[g.name] = gDiv;
            groupList.push({ g, gDiv });
            g.layerStableIds.forEach(sid => { layerGroupMap[sid] = idx; });
        });

        // fx번들 래퍼 생성 (효과 한 몸 — 눌림/나타남). groupId와 독립적이며 그룹의 부분집합일 수 있다.
        // 효과를 한 요소에 걸어야 멤버가 같은 중심으로 함께 변형되므로 멤버를 이 래퍼의 자식으로 모은다.
        // 래퍼는 캔버스 전체 크기라 transform-origin을 멤버 bbox 중심으로 잡아야 scale이 묶음 중앙 기준으로 동작한다.
        const fxBySid = {};
        const fxList = [];
        (c.fxGroups || []).forEach(fx => {
            const hasPress = !!(fx.press && fx.press.enabled);
            const hasAnim = !!(fx.cssAnimation && fx.cssAnimation.enabled);
            if (!hasPress && !hasAnim) return;
            const memberLayers = c.layers.filter(l => fx.layerStableIds.includes(l.stableId));
            if (!memberLayers.length) return;
            const maxZ = memberLayers.reduce((mx, l) => Math.max(mx, l.zIndex || 0), 0);
            const fxDiv = document.createElement('div');
            fxDiv.dataset.fxGroup = fx.name || '';
            fxDiv.style.cssText = `position:absolute;top:0;left:0;width:${w}px;height:${contentH}px;pointer-events:none;z-index:${maxZ};transform-origin:center center;`;
            let nX = Infinity, nY = Infinity, xX = -Infinity, xY = -Infinity;
            memberLayers.forEach(l => {
                const bw = (l.visual?.width || l.visual?.model?.shape?.width || 0) * (l.scale || 1) * (l.scaleX || 1);
                const bh = (l.visual?.height || l.visual?.model?.shape?.height || 0) * (l.scale || 1) * (l.scaleY || 1);
                const lx = l.x || 0, ly = l.y || 0;
                nX = Math.min(nX, lx); nY = Math.min(nY, ly);
                xX = Math.max(xX, lx + bw); xY = Math.max(xY, ly + bh);
            });
            if (isFinite(nX) && xX > nX) fxDiv.style.transformOrigin = `${(nX + xX) / 2}px ${(nY + xY) / 2}px`;
            if (hasPress) applyPressEffect(fxDiv, { enabled: true, params: { scale: fx.press.scale ?? 95, brightness: fx.press.brightness ?? 95, transitionMs: fx.press.transitionMs ?? 100 } }, {});
            if (hasAnim) applyCssAnimationEffect(fxDiv, this._gateIntroFx(normalizeCssAnimationEffect({ cssAnimation: fx.cssAnimation })));
            fxList.push({ fxDiv, memberSids: new Set(fx.layerStableIds) });
            fx.layerStableIds.forEach(sid => { fxBySid[sid] = fxDiv; });
        });

        // ── 오브젝트 마스크 컨테이너 (maskParentId) — 자식은 부모 실루엣 밖에 그려질 수 없다 ──
        // 컨테이너=뷰포트 전체(z=부모 zIndex, 부모 뒤 DOM 순서 → 부모 위에 그려짐), 내부 클리핑 평면에
        // 자식을 절대좌표 그대로 담는다. 부모 rotation 은 평면 transform 이 함께 회전(유니티 부모 좌표계).
        // 마스크 자식은 "부모의 배경" — 부모 몸체(inner) 안의 클리핑 평면에 담긴다.
        // 평면이 몸체 안이므로 부모의 scale/press/등장/회전이 자식에게 자동 상속되고,
        // 부모가 그룹/fx 래퍼로 들어가도 자식이 DOM 상 함께 따라간다(별도 규칙 불필요).
        // 몸체는 buildVisual 이후에야 존재하므로 배치를 뒤로 미루고 여기서는 대기열만 만든다.
        const layersBySid = {};
        (c.layers || []).forEach(l => { if (l.stableId) layersBySid[l.stableId] = l; });
        const maskParentOf = (l) => {
            if (!l.maskParentId) return null;
            const p = layersBySid[l.maskParentId];
            return (p && !p.maskParentId) ? p : null;   // 부모 미존재/2단계 중첩 → 마스크 미적용(자식은 일반 렌더)
        };
        const maskBodies = {};    // parent stableId → 부모 몸체 엘리먼트
        const maskPending = [];   // { child, childEl }

        const appendLayer = (l, target) => {
            const layerEl = this._buildLayerEl(l);
            if (l.hasMaskChildren) {
                const body = layerEl.querySelector('.ui-visual-body');
                if (body) maskBodies[l.stableId] = body;
            }
            if (maskParentOf(l)) { maskPending.push({ child: l, childEl: layerEl }); return; }
            const fxDiv = fxBySid[l.stableId];
            const gIdx = layerGroupMap[l.stableId];
            if (fxDiv) {
                layerEl.style.pointerEvents = 'auto';
                fxDiv.appendChild(layerEl);
            } else if (gIdx !== undefined && groupList[gIdx]) {
                layerEl.style.pointerEvents = 'auto';
                groupList[gIdx].gDiv.appendChild(layerEl);
            } else if (isScrollable && l.scrollFixed) {
                layerEl.style.pointerEvents = 'auto';
                pinWrap().appendChild(layerEl);
            } else {
                target.appendChild(layerEl);
            }
        };

        // 부모 몸체 안에 평면(+호스트)을 만들고 자식을 담는다. 좌표는 부모 로컬(중심 아닌 좌상단 기준).
        //   몸체는 이제 미스케일 크기(scale=CSS transform 그라운드 룰) — 배율은 부모 scaleWrap 이 담당하므로
        //   평면 박스도 미스케일이고 호스트에 별도 배율을 걸지 않는다(에디터 _maskHostFor 와 동일 기하).
        const maskHostFor = (parent) => {
            const body = maskBodies[parent.stableId];
            if (!body) return null;
            if (body._uiMaskHost) return body._uiMaskHost;
            const pb = contractLayerBounds(parent);
            const sc = parent.scale || 1;
            const psx = ((parent.scaleX ?? 1) * sc) || 1;
            const psy = ((parent.scaleY ?? 1) * sc) || 1;
            // 로컬 bounds = 몸체 박스(좌상단 0,0, 미스케일) — contractLayerBounds 는 배율 포함이므로 되돌린다.
            const plane = buildMaskClipPlane(parent, (p) => this._resolveAssetPath(p),
                { x: 0, y: 0, w: pb.w / psx, h: pb.h / psy }, { local: true });
            if (!plane) return null;
            plane.className = 'ui-mask-plane';
            plane.style.pointerEvents = 'none';
            plane.style.zIndex = String(parent.maskPlaneZIndex ?? 0);
            const host = document.createElement('div');
            host.className = 'ui-mask-scale-host';
            host.style.cssText = 'position:absolute;top:0;left:0;';
            plane.appendChild(host);
            body.appendChild(plane);
            // 스텐실 전용 부모 — 몸체 자체 페인트만 숨기고 평면은 되살린다(visibility 는 자손에서 재활성 가능)
            if (parent.maskShowGraphic === false) {
                body.style.visibility = 'hidden';
                plane.style.visibility = 'visible';
            }
            body._uiMaskHost = { plane, host, pb: { x: 0, y: 0, w: pb.w / psx, h: pb.h / psy }, psx, psy };
            return body._uiMaskHost;
        };
        const placeMaskChildren = () => {
            maskPending.forEach(({ child, childEl }) => {
                const parent = maskParentOf(child);
                const mh = parent && maskHostFor(parent);
                if (!mh) {
                    // 평면 생성 실패(부모 크기 0/몸체 없음) → 클리핑 없이 일반 렌더. 조용히 사라지지 않게 알린다.
                    console.warn('[SceneRenderer] 마스크 클리핑 평면 생성 실패 — 자식이 클리핑 없이 렌더됨:',
                        child.stableId, '→', child.maskParentId);
                    root.appendChild(childEl);
                    return;
                }
                // 부모 로컬 좌표 — 부모 배율은 부모 scaleWrap 상속으로 적용된다(에디터와 동일)
                const cb = contractLayerBounds(child);
                const lx = (child.x || 0) - (parent.x || 0);
                const ly = (child.y || 0) - (parent.y || 0);
                childEl.style.left = lx + 'px';
                childEl.style.top = ly + 'px';
                childEl.style.zIndex = '';   // 평면 내부에선 부모 로컬 순서만 의미가 있다
                childEl.style.pointerEvents = 'auto';
                mh.host.appendChild(childEl);
                // Mask — Tile(무한 패턴 채움, 이미지 전용)과 Flow(흘러가기 모션)는 독립. tile=정적/스크롤 패턴, 비타일 Flow=1회·loop 통과
                const flow = normalizeMaskFlowCfg(child.maskFlow);
                if (!flow) return;
                // 호스트 배율이 1 이 되었으므로(부모 scaleWrap 상속) 자식 박스도 나누지 않는다 — 에디터 _cbLocal 과 동일
                const cbLocal = { x: lx, y: ly, w: cb.w, h: cb.h };
                if (flow.tiled && child.layerType === 'image') {
                    // 정적 패턴(Flow off) 또는 스크롤 패턴(Flow on) — 모션은 buildMaskFlowTileEl 이 flow.enabled 로 판정
                    // 경로는 image → visual 순으로 폴백 — 이미지 렌더(_buildLayerEl)·부모 실루엣(buildMaskClipPlane)과 동일 규약.
                    // image.exportPath 만 읽으면 visual 에만 경로가 실린 케이스에서 타일이 조용히 사라진다.
                    const tileSrc = this._resolveAssetPath(child.image?.exportPath || child.visual?.exportPath || '');
                    const tileEl = buildMaskFlowTileEl(tileSrc, mh.pb, cbLocal, flow);
                    if (tileEl) {
                        mh.host.appendChild(tileEl);
                        childEl.style.opacity = '0';
                        childEl.style.pointerEvents = 'none';
                    }
                } else if (flow.enabled) {
                    // 비타일(또는 비이미지) + Flow 켜짐 → 통과 이동
                    applyMaskFlow(childEl, { ...flow, tiled: false }, mh.pb, cbLocal);
                }
            });
        };

        const sceneAnimationItems = Array.isArray(c.sceneAnimations) ? c.sceneAnimations : [];
        this._timelineAnimationTargets = new Set();
        this._timelineEnterTargets = new Set();
        sceneAnimationItems.forEach(item => {
            if (item?.type !== 'object-animation' || !item.targetStableId || item.enabled === false) return;
            this._timelineAnimationTargets.add(item.targetStableId);
            const preset = getCssAnimationPreset(item.cssPresetId || item.presetId || 'fade-in');
            if ((preset?.phase || 'attention') === 'enter') this._timelineEnterTargets.add(item.targetStableId);
            // 이펙트 CSS(animate.css)를 빌드 시점에 선주입 — reveal 게이트(_whenRenderResourcesReady)가
            // 로드 완료까지 공개를 지연한다. 재생 시점(첫 applyCssAnimationEffect) 주입이면
            // 스타일 도착 전 visibility 해제로 원본이 그대로 노출됐다가 fade-in 시작(플리커).
            ensureCssEffectProvider(preset?.provider || 'animate.css');
        });

        const sorted = [...c.layers].sort((a, b) => (a.zIndex || 0) - (b.zIndex || 0));
        sorted.forEach(l => appendLayer(l, root));

        // fx번들 래퍼 배치: 멤버가 한 그룹에 속하면 그 그룹 래퍼 안에(중첩), 아니면 root 직속.
        fxList.forEach(({ fxDiv, memberSids }) => {
            if (fxDiv.children.length === 0) return;
            // 멤버 중 하나라도 핀이면 번들째 핀 — 번들 래퍼가 배치를 독점하므로 개별 핀이 묻히지 않게 한다
            if (isScrollable && (c.layers || []).some(l => l.scrollFixed && memberSids.has(l.stableId))) {
                pinnedGDivs.push(fxDiv);
                return;
            }
            let parent = root;
            const gIdxs = new Set([...memberSids].map(sid => layerGroupMap[sid]).filter(v => v !== undefined));
            if (gIdxs.size === 1) {
                const gi = [...gIdxs][0];
                if (groupList[gi]) parent = groupList[gi].gDiv;
            }
            parent.appendChild(fxDiv);
        });

        // 마스크 자식 배치 — 부모 몸체가 모두 만들어진 뒤 각 부모의 클리핑 평면 안에 담는다.
        // 평면이 몸체 안이라 별도 컨테이너/z 배치가 필요 없다(부모의 z·그룹·번들 소속을 그대로 상속).
        placeMaskChildren();

        // 그룹 래퍼 배치 — scrollFixed(핀) 그룹은 스크롤 씬에서 root 밖(outerWrap)에 붙여 스크롤 제외
        groupList.forEach(({ g, gDiv }) => {
            if (gDiv.children.length === 0) return;
            if (isScrollable && g.scrollFixed) pinnedGDivs.push(gDiv);
            else root.appendChild(gDiv);
        });

        this._rootEl = root;

        if (isScrollable) {
            const outerWrap = document.createElement('div');
            outerWrap.style.cssText = `position:absolute;inset:0;width:${vw}px;height:${vh}px;overflow:hidden;`;
            // 스크롤 영역은 safeArea(top/bottom) 만큼 밀어내어 nav 가 가리는 공간을 콘텐츠 노출 영역에서 제외
            const scrollInner = document.createElement('div');
            scrollInner.className = 'sr-scroll-inner';
            scrollInner.style.cssText = `position:absolute;top:${safeTop}px;left:0;width:${vw}px;height:${effViewH}px;overflow-y:scroll;overflow-x:hidden;-webkit-overflow-scrolling:touch;scrollbar-width:none;-ms-overflow-style:none;`;
            scrollInner.appendChild(root);
            outerWrap.appendChild(scrollInner);
            // 핀 그룹 — scrollInner 뒤 DOM 순서로 항상 위. safeTop 만큼 내려 스크롤 0 시점의 자리 그대로 고정.
            pinnedGDivs.forEach(gDiv => {
                if (safeTop > 0) gDiv.style.top = safeTop + 'px';
                outerWrap.appendChild(gDiv);
            });
            this._el = outerWrap;
        } else {
            // 비스크롤이지만 safeArea 가 있으면 root 를 밀어내야 콘텐츠가 nav 와 겹치지 않음
            root.style.position = 'absolute';
            if (safeTop > 0)    root.style.top    = safeTop + 'px';
            if (safeBottom > 0) root.style.bottom = safeBottom + 'px';
            this._el = root;
        }

        // 그룹 위젯(토글/슬라이더) 레지스트리 — 핀 그룹 포함 모든 엘리먼트가 최종 트리에 들어온 뒤 해석
        this._initWidgets(c, this._el);
    }

    _buildNavigationDOM() {
        const c = this._contract;
        const vw = c.viewport?.width || 390;
        const vh = c.viewport?.height || 844;
        const anchor = c.navAnchor || 'bottom';
        const ox = c.navOffsetX || 0;
        const oy = c.navOffsetY || 0;
        const nw = c.navBarWidth || vw;
        const nh = c.navBarHeight || 80;

        this._injectCSS(false);

        // 외곽 컨테이너 (viewport 크기, position:relative 로 nav overlay 의 absolute 기준)
        const root = document.createElement('div');
        root.id = c.sceneId;
        root.style.cssText = `position:relative;width:${vw}px;height:${vh}px;overflow:hidden;opacity:0;transition:opacity 0.3s ease;z-index:5;background:transparent;`;

        // Scene Host: 매칭된 씬 contract 가 마운트될 영역 (viewport 전체)
        const host = document.createElement('div');
        host.className = 'sr-nav-host';
        host.style.cssText = `position:absolute;inset:0;width:${vw}px;height:${vh}px;overflow:hidden;`;
        root.appendChild(host);
        this._navHostEl = host;
        this._navHostInner = null;

        // 터치 스와이프로 탭 전환 (축 잠금 + 임계치). passive 로 스크롤은 방해하지 않음.
        {
            let sx = 0, sy = 0, locked = null, valid = false;
            const THRESHOLD = 50;
            host.addEventListener('touchstart', (e) => {
                const t = e.touches[0]; if (!t) return;
                sx = t.clientX; sy = t.clientY; locked = null; valid = true;
            }, { passive: true });
            host.addEventListener('touchmove', (e) => {
                if (!valid) return;
                const t = e.touches[0]; if (!t) return;
                const dx = t.clientX - sx, dy = t.clientY - sy;
                if (locked === null) {
                    const ax = Math.abs(dx), ay = Math.abs(dy);
                    if (ax < 10 && ay < 10) return;
                    const a = this._contract?.navAnchor || 'bottom';
                    const horiz = (a === 'top' || a === 'bottom');
                    const userAxis = ax > ay ? 'x' : 'y';
                    if ((horiz && userAxis !== 'x') || (!horiz && userAxis !== 'y')) {
                        valid = false; // 스크롤 의도 — 탭 전환 취소
                        return;
                    }
                    locked = userAxis;
                }
            }, { passive: true });
            host.addEventListener('touchend', (e) => {
                if (!valid || !locked) { valid = false; return; }
                const t = e.changedTouches && e.changedTouches[0];
                valid = false;
                if (!t) return;
                const delta = locked === 'x' ? (t.clientX - sx) : (t.clientY - sy);
                if (Math.abs(delta) < THRESHOLD) return;
                const tabs = this._contract?.tabs || [];
                if (!tabs.length) return;
                const order = tabs.map(tb => tb.id);
                const cur = order.indexOf(this._activeTab);
                if (cur < 0) return;
                // delta < 0 (왼쪽/위로 스와이프) → 다음 탭; > 0 → 이전 탭
                const next = delta < 0 ? cur + 1 : cur - 1;
                if (next < 0 || next >= order.length) return;
                this.switchTab(order[next]);
            });
        }

        // Nav Overlay (anchor + offset 으로 floating)
        const navOverlay = document.createElement('div');
        navOverlay.className = 'sr-nav-overlay';
        let navCss = `position:absolute;width:${nw}px;height:${nh}px;background:${c.navBgColor || 'rgba(22,33,62,0.95)'};z-index:1000;pointer-events:auto;`;
        switch (anchor) {
            case 'top':    navCss += `top:${oy}px;left:${ox}px;`; break;
            case 'bottom': navCss += `bottom:${oy}px;left:${ox}px;`; break;
            case 'left':   navCss += `top:${oy}px;left:${ox}px;`; break;
            case 'right':  navCss += `top:${oy}px;right:${ox}px;`; break;
        }
        navOverlay.style.cssText = navCss;

        // 배경 이미지(navBgImage 정식 필드) — 색 위에 겹치는 배경 레이어(9-slice/stretch 는 공유 빌더 단일 소스).
        // 첫 자식으로 넣어 탭바/자유 배치 레이어보다 항상 뒤에 그려진다.
        if (c.navBgImage && c.navBgImage.imagePath) {
            const navBgEl = buildNavBgEl(c.navBgImage, this._resolveAssetPath(c.navBgImage.imagePath), nw, nh, { sliceBitmap: this._sliceBitmap });
            if (navBgEl) navOverlay.appendChild(navBgEl);
        }

        // 동적 탭바 — navTabBar.enabled 시 nav overlay 전체에 탭바 마운트 (자유 배치 레이어와 공존 가능)
        this._navTabBarCtl = null;
        if (c.navTabBar && c.navTabBar.enabled && (c.tabs || []).length) {
            navOverlay.style.overflow = 'visible'; // 인디케이터/아이콘의 바 밖 돌출 허용
            const tbCfg = normalizeNavTabBar(c.navTabBar);
            const ctl = buildNavTabBar({
                tabs: (c.tabs || []).map(t => ({
                    id: t.id,
                    label: t.label || t.id,
                    iconSrc: t.iconPath ? this._resolveAssetPath(t.iconPath) : '',
                    iconActiveSrc: t.iconActivePath ? this._resolveAssetPath(t.iconActivePath) : '',
                })),
                config: tbCfg,
                indicatorSrc: (tbCfg.indicator.type === 'image' && tbCfg.indicator.imagePath)
                    ? this._resolveAssetPath(tbCfg.indicator.imagePath) : '',
                vertical: (anchor === 'left' || anchor === 'right'),
                activeTabId: c.defaultTabId || c.tabs[0].id,
                onTabClick: (id) => this.switchTab(id),
            });
            navOverlay.appendChild(ctl.el);
            this._navTabBarCtl = ctl;
        }

        // Nav 내부 layers — 각 layer 의 x,y 는 viewport 절대좌표이므로 nav rect 기준으로 변환
        const navRect = (() => {
            switch (anchor) {
                case 'top':    return { x: ox, y: oy };
                case 'bottom': return { x: ox, y: vh - nh - oy };
                case 'left':   return { x: ox, y: oy };
                case 'right':  return { x: vw - nh - ox, y: oy };
            }
            return { x: 0, y: 0 };
        })();

        const sceneAnimationItems = Array.isArray(c.sceneAnimations) ? c.sceneAnimations : [];
        this._timelineAnimationTargets = new Set();
        this._timelineEnterTargets = new Set();
        sceneAnimationItems.forEach(item => {
            if (item?.type !== 'object-animation' || !item.targetStableId || item.enabled === false) return;
            this._timelineAnimationTargets.add(item.targetStableId);
            const preset = getCssAnimationPreset(item.cssPresetId || item.presetId || 'fade-in');
            if ((preset?.phase || 'attention') === 'enter') this._timelineEnterTargets.add(item.targetStableId);
            // 이펙트 CSS(animate.css)를 빌드 시점에 선주입 — reveal 게이트(_whenRenderResourcesReady)가
            // 로드 완료까지 공개를 지연한다. 재생 시점(첫 applyCssAnimationEffect) 주입이면
            // 스타일 도착 전 visibility 해제로 원본이 그대로 노출됐다가 fade-in 시작(플리커).
            ensureCssEffectProvider(preset?.provider || 'animate.css');
        });

        // tabIds 가 없는 레이어(navbar 등 모든 탭 공통)는 navOverlay 에 고정 배치.
        // tabIds 가 있는 레이어는 전경 슬라이드 호스트에서 탭별로 렌더(콘텐츠와 함께 슬라이드).
        this._navScopedLayers = [];
        const sorted = [...(c.layers || [])].sort((a, b) => (a.zIndex || 0) - (b.zIndex || 0));
        sorted.forEach(l => {
            const scope = Array.isArray(l.tabIds) ? l.tabIds : [];
            if (scope.length) { this._navScopedLayers.push(l); return; }
            const layerEl = this._buildLayerEl(l);
            // viewport 절대 좌표 → nav overlay 내부 좌표
            layerEl.style.left = `${(l.x || 0) - navRect.x}px`;
            layerEl.style.top  = `${(l.y || 0) - navRect.y}px`;
            navOverlay.appendChild(layerEl);
        });

        // 전경 슬라이드 호스트: 콘텐츠(host) 위, navbar(navOverlay) 아래.
        // 스코프 오브젝트가 탭별 inner 로 마운트되어 콘텐츠와 동일하게 슬라이드한다.
        const fgHost = document.createElement('div');
        fgHost.className = 'sr-nav-fg-host';
        fgHost.style.cssText = `position:absolute;inset:0;width:${vw}px;height:${vh}px;overflow:hidden;z-index:500;pointer-events:none;`;
        root.appendChild(fgHost);
        this._navFgHostEl = fgHost;
        this._navFgInner = null;

        root.appendChild(navOverlay);

        this._rootEl = root;
        root.style.position = 'absolute';
        this._el = root;

        // 기본 탭 활성화 (matched scene 마운트)
        const defaultId = c.defaultTabId || (c.tabs && c.tabs[0] ? c.tabs[0].id : null);
        if (defaultId) {
            // _activeTab 을 null 로 두어 switchTab 이 실제로 동작하도록
            this._activeTab = null;
            this.switchTab(defaultId);
        }
    }

    /**
     * 레이어의 시각적 내부 컨텐츠 엘리먼트를 빌드해서 반환.
     * 에디터와 게임이 동일한 렌더링 코드를 공유하기 위한 단일 소스.
     *
     * @param {object} layer - contract 형식의 레이어 데이터
     * @returns {HTMLElement} 시각적 컨텐츠 엘리먼트 (component inner div 또는 image/wrapDiv)
     */
    /** 인트로 억제 모드에서 1회성(mount) css 애니메이션을 무효화 — loop 형(상시 연출)은 그대로 통과. */
    _gateIntroFx(effect) {
        if (this._introAnimations || !effect?.enabled || effect.params?.loop) return effect;
        return { enabled: false };
    }

    buildVisual(layer) {
        const _sc = layer.scale || 1;
        const _sx = (layer.scaleX !== undefined ? layer.scaleX : 1) * _sc;
        const _sy = (layer.scaleY !== undefined ? layer.scaleY : 1) * _sc;
        const timelineControlsCss = !!(layer.stableId && this._timelineAnimationTargets?.has(layer.stableId));

        // 좌우/상하 반전: 시각 콘텐츠를 감싸는 래퍼에 scale(-1) 적용.
        // press/spin 등이 콘텐츠 자체의 transform 을 동적으로 덮어쓰므로 별도 래퍼에서 처리.
        // 회전(rotWrap)은 바깥에서 감싸므로 rotate(flip(content)) 순서로 합성된다.
        const _flipWrap = (result) => {
            if (!layer.flipX && !layer.flipY) return result;
            const fw = document.createElement('div');
            fw.style.cssText = `display:inline-block;vertical-align:top;transform:scale(${layer.flipX ? -1 : 1},${layer.flipY ? -1 : 1});transform-origin:50% 50%;`;
            fw.appendChild(result);
            return fw;
        };
        // 텍스트 글자는 거울상이 되지 않도록 래퍼 반전을 상쇄(역-반전)한다. (이모지도 텍스트 content)
        const _flipText = (span) => {
            if (!layer.flipX && !layer.flipY) return;
            span.style.transform += ` scale(${layer.flipX ? -1 : 1},${layer.flipY ? -1 : 1})`;
        };

        if (layer.layerType === 'confetti') {
            return _flipWrap(this._buildConfettiVisual(layer, _sx, _sy));
        }

        if (layer.layerType === 'sprite') {
            return _flipWrap(this._buildSpriteVisual(layer, _sx, _sy));
        }

        if (layer.layerType === 'character') {
            return _flipWrap(this._buildCharacterVisual(layer));
        }

        if (layer.layerType === 'component' || layer.layerType === undefined) {
            const _v = { ...(layer.visual || {}) };
            if (layer.effects && !_v.effects) _v.effects = layer.effects;
            if (timelineControlsCss) {
                if (Array.isArray(_v.effects)) _v.effects = _v.effects.filter(e => e?.type !== 'css-animation');
                _v.cssAnimation = { ...(_v.cssAnimation || {}), enabled: false };
            } else if (!this._introAnimations) {
                // 인트로 억제 — 1회성 css 애니·파티클 버스트만 끔(loop 형 유지). effects 배열과 legacy cssAnimation 필드 양쪽 커버.
                if (Array.isArray(_v.effects)) {
                    _v.effects = _v.effects.map(e => ((e?.type === 'css-animation' || e?.type === 'particle-effect') && e.enabled && !e.params?.loop) ? { ...e, enabled: false } : e);
                }
                if (_v.cssAnimation?.enabled && !_v.cssAnimation.loop) _v.cssAnimation = { ..._v.cssAnimation, enabled: false };
            }
            const _model = _v.model;
            const v = (_sx !== 1 || _sy !== 1)
                ? (_model
                    ? { ..._v, model: { ..._model, shape: { ...(_model.shape || {}), width: Math.round(((_model.shape?.width) || _v.width || 100) * _sx), height: Math.round(((_model.shape?.height) || _v.height || 40) * _sy) } } }
                    : { ..._v, width: Math.round((_v.width || 100) * _sx), height: Math.round((_v.height || 40) * _sy) })
                : _v;
            const inner = document.createElement('div');
            this._applyComponentVisual(inner, v);
            // 몸체 표식 — 마스크 클리핑 평면의 삽입 지점(병합 텍스트/이미지와 같은 로컬 z 공간).
            // buildVisual 반환값은 flip 래퍼일 수 있어 호출자가 몸체를 이 클래스로 찾는다.
            inner.classList.add('ui-visual-body');

            // autoWrap 텍스트의 기준 폭 = 소속 오브젝트 폭 (v 는 이미 스케일 반영됨)
            const _objW = (v.model && v.model.shape && v.model.shape.width) || v.width || 100;

            (layer.texts || []).forEach((t, i) => {
                const span = document.createElement('span');
                span.className = `text-${i}`;
                span.textContent = t.staticContent || '';
                span.style.cssText = this._textCss(t, _sx, _sy, _objW);
                _flipText(span);
                const curved = applyTextCurve(span, t, _sx);
                if (!curved) applyTextGradientOverlay(span, t);
                if (t.bindingKey && !curved) {
                    if (t.staticContent && t.staticContent.includes('{value}')) span.dataset.bindingTemplate = t.staticContent;
                    if (!this._boundElements[t.bindingKey]) this._boundElements[t.bindingKey] = [];
                    this._boundElements[t.bindingKey].push(span);
                    // 사전 주입된 데이터가 있으면 디폴트 literal 대신 실제값으로 첫 페인트 (플리커 방지)
                    if (Object.prototype.hasOwnProperty.call(this._dataValues, t.bindingKey)) this._applyBoundText(span, this._dataValues[t.bindingKey]);
                }
                inner.appendChild(span);
            });

            (v.images || []).forEach(im => {
                if (!im.exportPath) return;
                const _imStyle = im.style || normalizeImageStyleModel(im);
                const filterStr = [imageTintFilterCss(_imStyle), imageShadowCss(_imStyle)].filter(Boolean).join(' ');
                const _imZi = im.zIndex != null ? `z-index:${im.zIndex};` : '';
                const _imW = Math.round((im.width||32) * _sx);
                const _imH = Math.round((im.height||32) * _sy);
                const _imOx = Math.round((im.offsetX||0) * _sx);
                const _imOy = Math.round((im.offsetY||0) * _sy);
                const _imSrc = this._resolveAssetPath(im.exportPath);
                const _imSlice = imageSliceCssText(_imStyle, _imSrc, _sx, _sy, _imW, _imH);
                const img = document.createElement(_imSlice ? 'div' : 'img');
                if (!_imSlice) { img.src = _imSrc; img.draggable = false; }
                if (_imSlice && this._sliceBitmap && !im.imageKey) applySliceBitmapUpgrade(img, _imStyle, _imSrc, _sx, _sy, _imW, _imH);
                img.style.cssText = `position:absolute;pointer-events:none;${_imSlice || `object-fit:${_imStyle.stretch ? 'fill' : 'contain'};`}width:${_imW}px;height:${_imH}px;left:calc(50% + ${_imOx}px);top:calc(50% + ${_imOy}px);transform:translate(-50%,-50%)${filterStr ? ';filter:'+filterStr : ''}${_imZi ? ';'+_imZi.slice(0,-1) : ''}`;
                if (im.imageKey) {
                    if (!this._boundImages[im.imageKey]) this._boundImages[im.imageKey] = [];
                    this._boundImages[im.imageKey].push(img);
                    if (Object.prototype.hasOwnProperty.call(this._dataValues, im.imageKey)) this._applyBoundImage(img, this._dataValues[im.imageKey]);
                }
                inner.appendChild(img);
            });
            if (layer.image) {
                const _liSrc = this._resolveAssetPath(layer.image.exportPath || '');
                // 박스 = 컴포넌트 inner 크기(v 는 이미 렌더 스케일 반영됨) — 렌더 클램프용
                const _objH = (v.model && v.model.shape && v.model.shape.height) || v.height || 40;
                const _liSlice = imageSliceCssText(layer.image.style, _liSrc, _sx, _sy, _objW, _objH);
                const img = document.createElement(_liSlice ? 'div' : 'img');
                if (!_liSlice) { img.src = _liSrc; img.draggable = false; }
                if (_liSlice && this._sliceBitmap && !layer.image.imageKey) applySliceBitmapUpgrade(img, layer.image.style, _liSrc, _sx, _sy, _objW, _objH);
                img.style.cssText = `position:absolute;inset:0;width:100%;height:100%;${_liSlice || `object-fit:${layer.image?.style?.stretch ? 'fill' : 'contain'};`}pointer-events:none;`;
                inner.appendChild(img);
            }
            return _flipWrap(inner);

        } else if (layer.layerType === 'image') {
            const cssAnimation = timelineControlsCss
                ? { enabled: false }
                : this._gateIntroFx(findEffect(layer.effects, 'css-animation') || normalizeCssAnimationEffect(layer));
            const particleEffect = this._gateIntroFx(findEffect(layer.effects, 'particle-effect') || normalizeParticleEffect(layer));
            const shineEffect = findEffect(layer.effects, 'shine') || normalizeShineEffect(layer);
            const _imgSrc = this._resolveAssetPath((layer.image?.exportPath) || (layer.visual?.exportPath) || '');
            const imageStyle = layer.image?.style || layer.visual?.style || normalizeImageStyleModel(layer);
            const _imgW = Math.round((layer.visual?.width || 64) * _sx);
            const _imgH = Math.round((layer.visual?.height || 64) * _sy);
            const _sliceCss = imageSliceCssText(imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH);
            const img = document.createElement(_sliceCss ? 'div' : 'img');
            if (_sliceCss) img.style.cssText = _sliceCss;
            else { img.src = _imgSrc; img.draggable = false; }
            // imageKey 바인딩 div 는 제외 — 동적 교체(_applyBoundImage)가 borderImageSource 를 갈아끼우는 경로 유지
            if (_sliceCss && this._sliceBitmap && !layer.image?.imageKey) applySliceBitmapUpgrade(img, imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH);
            const iw = _imgW + 'px';
            const ih = _imgH + 'px';
            // inline 이미지의 베이스라인 여백(폰트 line-height 의존)이 회전 래퍼 높이에 섞이면
            // 에디터/게임 페이지의 폰트 차이만큼 회전 중심 y 가 어긋난다 → 블록으로 고정.
            img.style.display = 'block';
            img.style.width = iw;
            img.style.height = ih;
            // 비율 토글: 기본=contain(원본 비율 고정), stretch=fill(width/height 대로 늘리기). slice 는 항상 박스를 채움
            if (!_sliceCss) img.style.objectFit = imageStyle?.stretch ? 'fill' : 'contain';
            if (layer.image?.imageKey) {
                if (!this._boundImages[layer.image.imageKey]) this._boundImages[layer.image.imageKey] = [];
                this._boundImages[layer.image.imageKey].push(img);
                if (Object.prototype.hasOwnProperty.call(this._dataValues, layer.image.imageKey)) this._applyBoundImage(img, this._dataValues[layer.image.imageKey]);
            }
            const _tintFilter = imageTintFilterCss(imageStyle);
            const _shadowFilter = imageShadowCss(imageStyle);
            img.style.filter = [_tintFilter, _shadowFilter].filter(Boolean).join(' ');
            const _imgPress = findEffect(layer.effects, 'press') || normalizePressEffect(layer);
            // 마스크 부모인 image 는 <img> 가 replaced element 라 클리핑 평면을 자식으로 담을 수 없어
            // 아래 wrapDiv 경로를 강제한다. 이때 press 를 img 가 아닌 wrapDiv 에 걸어야 평면(=마스크 자식)이
            // 부모와 함께 눌린다("자식은 부모의 배경" 규약, 컴포넌트가 inner 에 press 를 거는 것과 동일).
            // 마스크가 없는 image 는 기존 동작(img 에 press) 유지 — 기존 씬 외형 불변.
            const _maskHost = !!layer.hasMaskChildren;
            if (!_maskHost) applyPressEffect(img, _imgPress, { baseFilter: img.style.filter || '' });
            if (_maskHost || (layer.texts && layer.texts.length > 0)) {
                const wrapDiv = document.createElement('div');
                wrapDiv.classList.add('ui-visual-body'); // 마스크 평면 삽입 지점
                wrapDiv.style.cssText = `position:relative;width:${iw};height:${ih};`;
                if (_maskHost) applyPressEffect(wrapDiv, _imgPress, { baseFilter: '' });
                img.style.position = 'absolute'; img.style.top = '0'; img.style.left = '0';
                wrapDiv.appendChild(img);
                // 마스크 부모(_maskHost) 경로는 병합 텍스트 없이도 진입 — contract 는 빈 texts 를 삭제하므로 undefined 가드 필수
                (layer.texts || []).forEach(t => {
                    const span = document.createElement('span');
                    span.textContent = t.staticContent || '';
                    span.style.cssText = this._textCss(t, _sx, _sy, parseInt(iw, 10) || 0);
                    _flipText(span);
                    const curved = applyTextCurve(span, t, _sx);
                    if (!curved) applyTextGradientOverlay(span, t);
                    if (t.bindingKey && !curved) {
                        if (t.staticContent && t.staticContent.includes('{value}')) span.dataset.bindingTemplate = t.staticContent;
                        if (!this._boundElements[t.bindingKey]) this._boundElements[t.bindingKey] = [];
                        this._boundElements[t.bindingKey].push(span);
                        // 사전 주입된 데이터가 있으면 디폴트 literal 대신 실제값으로 첫 페인트 (플리커 방지)
                        if (Object.prototype.hasOwnProperty.call(this._dataValues, t.bindingKey)) this._applyBoundText(span, this._dataValues[t.bindingKey]);
                    }
                    wrapDiv.appendChild(span);
                });
                applyCssAnimationEffect(wrapDiv, cssAnimation);
                playParticleEffect(wrapDiv, particleEffect);
                applyShineEffect(wrapDiv, shineEffect, _sliceCss
                    ? {
                        maskBoxCss: imageSliceCssText(imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH, true),
                        maskBitmap: (this._sliceBitmap && !layer.image?.imageKey && shineEffect?.enabled)
                            ? composeSliceBitmap(imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH) : null,
                    }
                    : { maskSrc: _imgSrc, maskFit: imageStyle?.stretch ? '100% 100%' : 'contain' });
                return _flipWrap(wrapDiv);
            }
            if (particleEffect?.enabled || shineEffect?.enabled) {
                // particle-effect(예: ambient aura)는 span 자식을 el 에 appendChild 하는데,
                // <img> 는 replaced element 라 자식이 append는 되어도 화면에는 절대 그려지지 않는다.
                // → 텍스트 branch(1938행)와 동일하게 relative wrapper div 로 감싸서 자식이 렌더되게 한다.
                const wrapDiv = document.createElement('div');
                wrapDiv.style.cssText = `position:relative;width:${iw};height:${ih};`;
                img.style.position = 'absolute'; img.style.top = '0'; img.style.left = '0';
                wrapDiv.appendChild(img);
                applyCssAnimationEffect(wrapDiv, cssAnimation);
                playParticleEffect(wrapDiv, particleEffect);
                applyShineEffect(wrapDiv, shineEffect, _sliceCss
                    ? {
                        maskBoxCss: imageSliceCssText(imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH, true),
                        maskBitmap: (this._sliceBitmap && !layer.image?.imageKey && shineEffect?.enabled)
                            ? composeSliceBitmap(imageStyle, _imgSrc, _sx, _sy, _imgW, _imgH) : null,
                    }
                    : { maskSrc: _imgSrc, maskFit: imageStyle?.stretch ? '100% 100%' : 'contain' });
                return _flipWrap(wrapDiv);
            }
            applyCssAnimationEffect(img, cssAnimation);
            return _flipWrap(img);
        }
        return document.createElement('div');
    }

    // 스프라이트 애니메이션 레이어. 균일 셀 그리드 WebP 아틀라스를 캔버스에 프레임별로 그린다.
    // clip = { cellW, cellH, cols, rows, count, delays:[ms…], loop:0|N, playbackRate, startDelayMs }.
    // rAF 루프는 매 프레임 document.contains 검사로 자가종료(에디터 재렌더/씬 hide 시 노드 분리 → 정지) → 누수 없음.
    // 재생속도: canvas._spriteRate 곱연산(런타임 setSpriteRate / 에디터 슬라이더가 실시간 변경, 0=일시정지).
    // ── 캐릭터(조립 세트) ─────────────────────────────────────────────────────
    // layerType:'character' 레이어 = "캐릭터 메이커에서 조립한 한 세트"의 인스턴스.
    // 정의(몸통·소켓·파츠)는 별도 파일 characters/<id>.character.json 에 있고 여기서 조립만 한다.
    // 반환 엘리먼트에 __uiCharacter 를 달아 게임이 equip('hand_r','axe') 로 무기를 갈아끼울 수 있다.
    _buildCharacterVisual(layer) {
        const host = document.createElement('div');
        host.className = 'sr-character';
        host.style.cssText = 'position:relative;';
        const id = layer.characterId || '';
        // 인스턴스 장착 상태: 씬에서 준 오버라이드가 정의의 기본 장착을 덮는다.
        const equip = Object.assign({}, layer.equip || {});
        // 포즈키 → { el: 포즈 컨테이너, rest: 휴지 자세 } — 클립 재생이 transform 만 갱신한다.
        const poseEls = Object.create(null);
        let raf = null;
        let poseDelta = false;   // def.version >= 3 → 클립 포즈가 기본 자세 대비 델타(mount 에서 판정)

        // 레이어 하나를 "포즈 컨테이너"에 담아 붙인다. 컨테이너는 크기 0 의 좌표계 껍데기이고,
        // 애니메이션은 이 껍데기의 transform 만 바꾼다(내부 DOM 재조립 없음).
        const attach = (layer, zIndex) => {
            const cont = document.createElement('div');
            cont.className = 'sr-pose';
            if (layer.poseKey) cont.dataset.poseKey = layer.poseKey;
            const bounds = contractLayerBounds(layer);
            cont.style.cssText = 'position:absolute;left:0;top:0;width:0;height:0;'
                + `z-index:${zIndex};transform-origin:${characterPoseOrigin(layer, bounds)};`;
            // 표시 여부는 포즈 컨테이너가 전담(클립 hidden 트랙) — 내부에 display:none 이 박히면 해제 불가.
            cont.appendChild(this._buildLayerEl(layer.visible === false ? { ...layer, visible: true } : layer));
            if (layer.visible === false) cont.style.visibility = 'hidden';
            host.appendChild(cont);
            if (layer.poseKey) poseEls[layer.poseKey] = { el: cont, rest: layer, bounds };
        };

        const mount = (def) => {
            if (!def) return;
            poseDelta = (def.version || 2) >= 3;
            host.style.width = (def.width || 0) + 'px';
            host.style.height = (def.height || 0) + 'px';
            const merged = Object.assign({}, def.equip || {}, equip);
            host.innerHTML = '';
            Object.keys(poseEls).forEach(k => delete poseEls[k]);
            // 렌더 순서 규약: 슬롯의 z 가 "몸통 앞/뒤" 블록을 먼저 정하고, 레이어의 zIndex 는
            // 그 블록 안에서만 의미를 갖는다(= 슬롯 z 가 항상 이긴다).
            // 앞 슬롯끼리는 정의에 나온 슬롯 순서대로 겹친다(뒤 슬롯은 전부 몸통 아래, DOM 순서).
            const maxBaseZ = (def.base || []).reduce((m, l) => Math.max(m, l.zIndex || 1), 1);
            (def.base || []).forEach(l => attach(l, l.zIndex || 1));
            (def.sockets || []).forEach((s, si) => {
                const part = (def.parts || []).find(p => p.id === merged[s.id]);
                if (!part) return;
                // 파츠도 몸통과 같은 캐릭터 절대 좌표 — 슬롯은 교체 단위와 앞/뒤만 정한다.
                (part.layers || []).forEach(l => attach(l, (s.z === 'back') ? 0 : (maxBaseZ + 1 + si)));
            });
        };

        const stop = () => { if (raf) { cancelAnimationFrame(raf); raf = null; } };
        // 휴지 자세로 되돌린다 — 클립 종료/정지 공통.
        const resetPose = () => {
            Object.keys(poseEls).forEach(k => {
                const rec = poseEls[k];
                rec.el.style.transform = '';
                rec.el.style.visibility = rec.rest.visible === false ? 'hidden' : '';
                rec.wasHidden = rec.rest.visible === false;
            });
        };
        // 샘플된 포즈 맵을 화면에 반영. 클립이 언급하지 않은 레이어는 휴지 자세 유지.
        // hooks = { onShow, onHide } — 등장/퇴장 트랙이 바뀌는 프레임에서만 1회 호출(투사체 발사 인계).
        const applyPose = (pose, hooks) => {
            Object.keys(poseEls).forEach(k => {
                const rec = poseEls[k];
                const p = pose[k];
                rec.el.style.transform = p ? characterPoseCss(rec.rest, p, rec.bounds, poseDelta) : '';
                const hidden = (p ? !!p.hidden : rec.rest.visible === false);
                rec.el.style.visibility = hidden ? 'hidden' : '';
                // 전환 순간만 통지. 조준선 측정은 visibility 반영 뒤에 해도 되고(레이아웃 불변),
                // 그래야 "사라지는 프레임"의 최종 자세에서 발사각이 나온다.
                if (hooks && rec.wasHidden !== undefined && rec.wasHidden !== hidden) {
                    const cb = hidden ? hooks.onHide : hooks.onShow;
                    if (cb) cb(k, rec.el, characterAimWorld(rec.el));
                }
                rec.wasHidden = hidden;
            });
        };

        const def = SceneRenderer.characterDefs[id];
        if (def) {
            mount(def);
        } else if (id) {
            this._loadCharacterDef(id).then(loaded => {
                if (loaded) mount(loaded);
            });
        } else {
            console.warn('[SceneRenderer] character 레이어에 characterId 가 없습니다:', layer.stableId);
        }

        // 게임용 조작 핸들 — 무기 교체(equip)와 프레임 클립 재생(play).
        host.__uiCharacter = {
            characterId: id,
            equip: (socketId, partId) => {
                if (partId) equip[socketId] = partId;
                else delete equip[socketId];
                const d = SceneRenderer.characterDefs[id];
                if (d) mount(d);
                else console.warn('[SceneRenderer] 캐릭터 정의 미로드 — equip 이 반영되지 않았습니다:', id);
            },
            getEquip: () => Object.assign({}, equip),
            /** 프레임 클립 재생. name = 클립 이름 또는 id. opts.loop 로 정의값을 덮어쓴다.
             *  opts.onShow / opts.onHide (poseKey, el, aim) — 등장·퇴장 트랙 전환 시. aim = 조준선이
             *  있으면 { x, y, angleDeg }(client 좌표), 없으면 null. 투사체 발사 인계는 보통 onHide. */
            play: (name, opts = {}) => {
                const d = SceneRenderer.characterDefs[id];
                const clip = (d?.clips || []).find(c => c.name === name || c.id === name);
                if (!clip || !(clip.frames || []).length) {
                    console.warn('[SceneRenderer] 캐릭터 클립을 찾을 수 없습니다:', id, name);
                    return false;
                }
                stop();
                const loop = opts.loop !== undefined ? opts.loop : !!clip.loop;
                const dur = characterClipDuration(clip);
                if (dur <= 0) {
                    console.warn('[SceneRenderer] 캐릭터 클립 길이가 0 입니다(프레임 시각 확인):', id, name);
                    return false;
                }
                // 등장/퇴장 통지의 기준선은 휴지 자세 — 첫 프레임에서 이미 바뀌었다면 그것도 전환이다.
                Object.keys(poseEls).forEach(k => { poseEls[k].wasHidden = poseEls[k].rest.visible === false; });
                const t0 = performance.now();
                const rate = Number(opts.rate) > 0 ? Number(opts.rate) : 1; // 재생 배속 — 게임 진행속도 배수 연동용(등장/퇴장 훅·onEnd 도 같이 빨라진다)
                const step = (now) => {
                    let t = (now - t0) * rate;
                    if (t >= dur) {
                        if (loop) t = t % dur;
                        else {
                            applyPose(sampleCharacterClip(clip, dur), opts);   // 마지막 프레임 자세로 정지
                            raf = null;
                            if (opts.onEnd) opts.onEnd();
                            return;
                        }
                    }
                    applyPose(sampleCharacterClip(clip, t), opts);
                    raf = requestAnimationFrame(step);
                };
                raf = requestAnimationFrame(step);
                return true;
            },
            /** 재생 중지 + 소켓 원위치 */
            stop: () => { stop(); resetPose(); },
        };
        return host;
    }

    // 캐릭터 정의 로드 — publish 출력 폴더의 characters/<id>.character.json.
    // 같은 캐릭터를 여러 씬/여러 인스턴스가 쓰므로 전역 캐시(중복 fetch 방지, 인플라이트 공유).
    _loadCharacterDef(id) {
        if (SceneRenderer.characterDefs[id]) return Promise.resolve(SceneRenderer.characterDefs[id]);
        if (SceneRenderer._characterLoads[id]) return SceneRenderer._characterLoads[id];
        // 정의 경로 기준(characterBase)은 에셋 기준(basePath)과 별개다.
        // 정의는 publish 출력 폴더(scene-renderer.js 옆의 characters/)에, 이미지 exportPath 는
        // 프로젝트 루트 기준이라 하나의 기준으로 둘 다 담을 수 없다.
        const base = SceneRenderer.characterBase;
        const url = (base ? base.replace(/\/?$/, '/') : '') + 'characters/' + id + '.character.json';
        const pr = fetch(url)
            .then(r => {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.json();
            })
            .then(def => {
                // v1 = 소켓이 좌표를 갖던 옛 형식. 런타임은 변환하지 않는다(에디터에서 재발행이 정답).
                if ((def.version || 1) < 2) {
                    console.error('[SceneRenderer] 캐릭터 정의가 옛 형식(v' + (def.version || 1) + ')입니다 —'
                        + ' ui-editor 캐릭터 메이커에서 열고 저장해 재발행하세요:', id);
                }
                SceneRenderer.characterDefs[id] = def;
                return def;
            })
            .catch(e => {
                console.error('[SceneRenderer] 캐릭터 정의 로드 실패 — 캐릭터가 렌더되지 않습니다:', url, e);
                return null;
            })
            .finally(() => { delete SceneRenderer._characterLoads[id]; });
        SceneRenderer._characterLoads[id] = pr;
        return pr;
    }

    _buildSpriteVisual(layer, _sx, _sy) {
        const clip = layer.clip || layer.visual?.clip || {};
        const cellW = clip.cellW || layer.visual?.width || 64;
        const cellH = clip.cellH || layer.visual?.height || 64;
        const cols  = Math.max(1, clip.cols || 1);
        const count = Math.max(1, clip.count || (Array.isArray(clip.delays) ? clip.delays.length : 1));
        const delays = Array.isArray(clip.delays) && clip.delays.length ? clip.delays : null;
        const dispW = Math.round((layer.visual?.width || cellW) * _sx);
        const dispH = Math.round((layer.visual?.height || cellH) * _sy);

        const canvas = document.createElement('canvas');
        canvas.width = dispW; canvas.height = dispH;
        canvas.style.display = 'block';   // inline 베이스라인 여백 제거 — 회전 중심 y 어긋남 방지
        canvas.style.width = dispW + 'px';
        canvas.style.height = dispH + 'px';
        canvas.style.objectFit = 'contain';
        canvas._spriteRate = clip.playbackRate != null ? clip.playbackRate : 1;

        const ctx = canvas.getContext('2d');
        const atlas = new Image();
        const src = this._resolveAssetPath((layer.image?.exportPath) || (layer.visual?.exportPath) || layer.exportPath || '');
        atlas.onload = () => this._runSpriteLoop(canvas, ctx, atlas, { cellW, cellH, cols, count, delays, loop: clip.loop || 0, fps: clip.fps || 10, startDelay: Math.max(0, clip.startDelayMs || 0) });
        atlas.onerror = () => console.error('[scene-renderer] sprite 아틀라스 로드 실패:', src);
        atlas.src = src;
        return canvas;
    }

    // 자가종료 rAF 스프라이트 재생 루프. 노드가 DOM 에서 분리되면 다음 프레임에 스스로 멈춘다.
    // startDelay: 재생 시작 전 대기(ms, 벽시계 — playbackRate 무관). 대기 중엔 첫 프레임 고정 표시.
    // 같은 스프라이트 복사본들의 위상(리듬)을 어긋나게 할 때 사용.
    _runSpriteLoop(canvas, ctx, atlas, cfg) {
        const { cellW, cellH, cols, count, delays, loop, fps, startDelay } = cfg;
        const defDelay = Math.max(1, Math.round(1000 / (fps || 10)));
        let i = 0, acc = 0, last = 0, loopsDone = 0;
        const draw = () => {
            const col = i % cols, row = (i / cols) | 0;
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.drawImage(atlas, col * cellW, row * cellH, cellW, cellH, 0, 0, canvas.width, canvas.height);
        };
        const frame = (now) => {
            if (!document.contains(canvas)) return; // 노드 분리 → 자가종료(누수 방지)
            if (last === 0) last = now;
            const rate = canvas._spriteRate != null ? canvas._spriteRate : 1;
            acc += (now - last) * (rate > 0 ? rate : 0);
            last = now;
            let delay = (delays ? delays[i] : defDelay) || defDelay;
            let guard = 0;
            while (acc >= delay && guard++ < 1000) {
                acc -= delay;
                i++;
                if (i >= count) {
                    if (loop && ++loopsDone >= loop) { i = count - 1; draw(); return; } // 유한 루프 종료 → 마지막 프레임 고정
                    i = 0;
                }
                delay = (delays ? delays[i] : defDelay) || defDelay;
            }
            draw();
            requestAnimationFrame(frame);
        };
        draw();
        if (startDelay > 0) setTimeout(() => requestAnimationFrame(frame), startDelay);
        else requestAnimationFrame(frame);
    }

    // Confetti 레이어 시각화. 컨테이너 div 만 만들고, autoplay/loop 설정에 따라 파티클 재생.
    // triggerKey 가 있으면 data-confetti-trigger 부여 → playConfetti(key) 로 외부 트리거 가능.
    _buildConfettiVisual(layer, _sx, _sy) {
        const w = Math.round((layer.visual?.width || layer.width || 320) * (_sx || 1));
        const h = Math.round((layer.visual?.height || layer.height || 240) * (_sy || 1));
        const cfg = layer.confetti || layer.visual?.confetti || layer;
        const container = document.createElement('div');
        container.style.cssText = 'position:relative;width:' + w + 'px;height:' + h + 'px;overflow:visible;pointer-events:none;';
        if (cfg.triggerKey) container.dataset.confettiTrigger = cfg.triggerKey;
        const opts = {
            width: w, height: h,
            confettiPattern: cfg.confettiPattern || 'center-burst',
            particleCount: cfg.particleCount,
            duration: cfg.duration,
            spread: cfg.spread,
            velocity: cfg.velocity,
            colors: cfg.colors,
            sizeMin: cfg.sizeMin,
            sizeMax: cfg.sizeMax,
            shape: cfg.shape,
        };
        container._confettiOpts = opts;
        container._confettiCfg = { loop: !!cfg.loop, repeat: cfg.repeat, loopDelay: cfg.loopDelay };
        ensureConfettiKeyframes();
        const autoplay = cfg.autoplay !== false;
        if (autoplay || cfg.loop) {
            requestAnimationFrame(() => runConfettiPlayback(container, opts, container._confettiCfg));
        }
        return container;
    }

    /** 외부에서 confetti 레이어를 트리거. triggerKey 일치하는 모든 컨테이너 재생(repeat/loop 존중). */
    playConfetti(triggerKey) {
        if (!this._rootEl) return;
        const sel = '[data-confetti-trigger="' + triggerKey + '"]';
        const els = this._rootEl.querySelectorAll(sel);
        els.forEach(c => {
            if (c._confettiOpts) runConfettiPlayback(c, c._confettiOpts, c._confettiCfg || {});
        });
    }

    _buildLayerEl(layer) {
        const wrap = document.createElement('div');
        wrap.dataset.stableId = layer.stableId;
        const _sc = layer.scale || 1;
        const _sx = (layer.scaleX !== undefined ? layer.scaleX : 1) * _sc;
        const _sy = (layer.scaleY !== undefined ? layer.scaleY : 1) * _sc;
        wrap.style.cssText = `position:absolute;left:${layer.x}px;top:${layer.y}px;z-index:${layer.zIndex};`;
        if (layer.visible === false) wrap.style.display = 'none';
        // visibleBindingKey 는 위젯(visibility) 체계로 흡수되어 지원 종료 — 마이그레이션 없음.
        // 옛 contract 를 만나면 조용히 무시하지 않고 로그로 재저작 필요를 알린다.
        if (layer.visibleBindingKey) {
            console.warn('[SceneRenderer] visibleBindingKey 지원 종료 — ui-editor에서 위젯(표시)으로 재저작 후 재발행 필요:',
                layer.stableId, '→', layer.visibleBindingKey);
        }
        // 타임라인 enter 대상 숨김은 _runSceneAnimations 가 재생 시점에 해제한다 —
        // 인트로 억제 모드는 재생 자체가 없으므로 숨기지 않고 최종 상태로 노출.
        if (this._introAnimations && layer.stableId && this._timelineEnterTargets?.has(layer.stableId)) {
            wrap.style.visibility = 'hidden';
        }

        // Nav button role (navigation sceneType 의 layer 만 의미를 가짐)
        if (layer.navTabId) {
            const c = this._contract;
            const firstTabId = (c?.sceneType === 'navigation')
                ? (c.defaultTabId || (c.tabs && c.tabs[0] ? c.tabs[0].id : ''))
                : '';
            wrap.dataset.navTab = layer.navTabId;
            wrap.classList.toggle('active', layer.navTabId === firstTabId);
            wrap.style.cursor = 'pointer';
            wrap.addEventListener('click', () => this.switchTab(layer.navTabId));
        }

        // 그라운드 룰: scale 은 px 에 굽지 않고 CSS transform 으로만 적용한다(에디터 free-item 과 동일 파이프라인).
        // 굽기(Math.round)는 에디터와 최대 1px 크기 차이를 만들어 접합면 실금·9-slice 눈금선의 원인이었다.
        // scale 을 wrap 이 아닌 전용 scaleWrap 에 싣는 이유: wrap.transform/animation 은 슬라이더 위젯(translateX)·
        // 타임라인 spin(ui-spin)·object-animation(animate.css)이 덮어쓰는 슬롯이라 scale 과 공존할 수 없다.
        // 합성 순서 scale(rotate(content)) 도 에디터(.free-item > .rotate-wrap)와 동일.
        const _scaled = _sx !== 1 || _sy !== 1;
        const content = this.buildVisual(_scaled ? { ...layer, scale: 1, scaleX: 1, scaleY: 1 } : layer);
        // spinAnimation은 _applyComponentVisual 에서 visual 엘리먼트 자체에 적용된다 (단일 진입점).
        // 여기서는 layer.rotation (정적) 만 처리.
        let inner = content;
        // 조준선(투사체) — 꼬리·촉 두 점을 이미지와 **같은 변환 안**에 크기 0 요소로 심는다.
        // 발사 좌표·각도는 이 두 점의 getBoundingClientRect 로 측정한다(characterAimWorld):
        // 회전·배율·좌우반전이 몇 겹 얹혀도 브라우저가 합성해준 결과를 그대로 읽으므로 부호 실수가 없다.
        // 좌표는 미배율 원본 px(scale 은 바깥 scaleWrap 담당), 그리고 **회전보다 안쪽**이어야 한다
        // — 밖에 두면 레이어 자체 회전이 마커에 안 걸려 각도가 틀어진다.
        if (layer.aim) {
            // 미배율 원본 크기 — 도형 컴포넌트는 visual.width 가 없으므로 bounds 헬퍼를 배율 1로 재사용.
            const _ob = contractLayerBounds({ ...layer, scale: 1, scaleX: 1, scaleY: 1 });
            const _ow = _ob.w, _oh = _ob.h;
            const holder = document.createElement('div');
            holder.style.position = 'relative';   // 마커의 컨테이닝 블록 (조준선 있는 레이어에만 생김)
            holder.appendChild(inner);
            [['tail', layer.aim.x1, layer.aim.y1], ['tip', layer.aim.x2, layer.aim.y2]].forEach(([role, rx, ry]) => {
                const m = document.createElement('div');
                m.className = 'sr-aim-' + role;
                m.style.cssText = `position:absolute;left:${(rx || 0) * _ow}px;top:${(ry || 0) * _oh}px;width:0;height:0;`;
                holder.appendChild(m);
            });
            inner = holder;
        }
        if (layer.rotation) {
            const rotWrap = document.createElement('div');
            rotWrap.style.transform = `rotate(${layer.rotation}deg)`;
            rotWrap.style.transformOrigin = '50% 50%';
            // 배율 시 wrap 이 명시 폭(배율 포함)을 가져 블록 래퍼가 늘어난다 → 회전 중심 x 가
            // 에디터(.free-item = shrink-to-fit)와 달라짐. 콘텐츠 폭에 맞춰 동일 중심 유지.
            rotWrap.style.width = 'fit-content';
            rotWrap.appendChild(inner);
            inner = rotWrap;
        }
        if (_scaled) {
            // wrap 명시 크기 = 배율 포함 bounds — 타임라인 spin/animate.css 의 transform-origin 50% 가
            // (transform 은 레이아웃 크기를 안 바꾸므로) 미스케일 중심으로 어긋나는 것을 막는다.
            const _b = contractLayerBounds(layer);
            if (_b.w > 0 && _b.h > 0) { wrap.style.width = _b.w + 'px'; wrap.style.height = _b.h + 'px'; }
            const scaleWrap = document.createElement('div');
            scaleWrap.className = 'sr-scale-wrap';
            scaleWrap.style.cssText = `transform:scale(${_sx},${_sy});transform-origin:0 0;`;
            scaleWrap.appendChild(inner);
            wrap.appendChild(scaleWrap);
        } else {
            wrap.appendChild(inner);
        }

        // Wire declared events
        (layer.events || []).forEach(ev => {
            wrap.addEventListener(ev.trigger || 'click', (e) => {
                const evtName = ev.eventName || (layer.stableId + ':' + (ev.trigger || 'click'));
                // 흐름도에서 씬 이동이 선언된(targetSceneUuid/branches) 이벤트인데 구독자가 없으면
                // 게임 코드 미배선 — 흐름도와 게임의 불일치를 런타임 클릭 시점에 즉시 판정한다.
                if (this._isFlowEventUnwired(ev, evtName)) {
                    console.warn('[SceneRenderer] 흐름도 연결 이벤트에 구독자가 없습니다(게임 미배선):', evtName,
                        ev.targetSceneUuid ? { targetSceneUuid: ev.targetSceneUuid } : { branches: ev.branches });
                }
                // 클릭 트리거 타임라인(개봉 연출 등)과 같은 클릭이면 연출 종료까지 지연 발화 — _timelineEmitDeferMs 참조
                const pending = this._timelinePendingEmits || (this._timelinePendingEmits = new Set());
                if (pending.has(evtName)) return; // 지연 발화 대기 중(연출 재생 중) 재클릭 무시
                const deferMs = this._timelineEmitDeferMs(layer.stableId);
                if (deferMs > 0) {
                    pending.add(evtName);
                    console.info('[SceneRenderer] 타임라인 연출 종료까지 이벤트 발화 지연:', evtName, deferMs + 'ms');
                    setTimeout(() => {
                        pending.delete(evtName);
                        if (!this._rootEl?.isConnected) return; // 지연 중 hide/reload 되면 발화 취소
                        this._emit(evtName, { stableId: layer.stableId, originalEvent: e });
                    }, deferMs);
                    return;
                }
                this._emit(evtName, { stableId: layer.stableId, originalEvent: e });
            });
        });

        return wrap;
    }

    _applyComponentVisual(el, v) {
        const model = componentModelFromVisual(v);
        const effects = componentEffectsFromVisual(v);
        const shape = model.shape || {};
        const fill = model.fill || {};
        const border = model.border || {};
        const mask = model.mask || {};
        const shapeType = shape.type || 'rectangle';
        const isCircle = shapeType === 'circle';
        const isPill = shapeType === 'pill';
        const isRibbon = shapeType === 'ribbon';
        const isNotch = shapeType === 'notch';
        const isRibbonL = shapeType === 'ribbon-left';
        const isNotchL = shapeType === 'notch-left';
        const isRing = shapeType === 'ring';
        const isHollowRect = shapeType === 'hollow-rect';
        const isTopRoundRect = shapeType === 'top-round-rect';
        const isHollow = isRing || isHollowRect;
        const w = (isCircle || isRing) ? Math.max(shape.width || 60, shape.height || 60) : (shape.width || 100);
        const h = (isCircle || isRing) ? Math.max(shape.width || 60, shape.height || 60) : (shape.height || 40);
        let radius = shape.radius || 0;
        if (isCircle || isRing) radius = w / 2;
        else if (isPill) radius = h / 2;
        else if (isRibbon || isRibbonL || isNotch || isNotchL) radius = 0;
        const radiusCss = isTopRoundRect ? `${radius}px ${radius}px 0 0` : `${radius}px`;

        // this 가 null 일 수 있음(SceneRenderer.utils.applyComponentVisual 진입점). 안전하게 항등 처리.
        const self = this;
        const resolveAsset = (p) => (self && self._resolveAssetPath) ? self._resolveAssetPath(p) : p;
        const fillCss = componentFillCss(fill, resolveAsset);

        const isClipped = isRibbon || isNotch || isRibbonL || isNotchL;
        const { shadows, filterEffects } = componentShadowCss(model, isClipped);

        const ribbonNotch = shape.notch ?? 20;

        if (isHollow) {
            const oldBg = el.querySelector(':scope > .ribbon-bg-layer');
            if (oldBg) oldBg.remove();
            const thickness = shape.hollowThickness || 8;
            el.style.cssText = [
                `position:relative;display:flex;align-items:center;justify-content:center;flex-shrink:0;box-sizing:border-box;`,
                `width:${w}px;height:${h}px;border-radius:${radiusCss};background:transparent;`,
                `border:${thickness}px solid ${fill.color1 || '#4a90d9'};`,
                shadows.length ? `box-shadow:${shadows.join(',')};` : '',
                border.width > 0 ? `outline:${border.width}px solid ${border.color || '#fff'};outline-offset:0;` : '',
            ].join('');
        } else if (isClipped) {
            // filter는 부모(el)에, clip-path는 자식(.ribbon-bg)에 분리
            // CSS 렌더링 순서: filter → clip-path 이므로 같은 엘리먼트에 두면 shadow가 잘림
            el.style.cssText = [
                `position:relative;display:flex;align-items:center;justify-content:center;flex-shrink:0;overflow:visible;`,
                `width:${w}px;height:${h}px;`,
                filterEffects.length ? `filter:${filterEffects.join(' ')};` : '',
            ].join('');
            const clipPoly = isRibbon  ? `polygon(0% 0%,calc(100% - ${ribbonNotch}px) 0%,100% 50%,calc(100% - ${ribbonNotch}px) 100%,0% 100%)`
                : isRibbonL ? `polygon(${ribbonNotch}px 0%,100% 0%,100% 100%,${ribbonNotch}px 100%,0% 50%)`
                : isNotchL  ? `polygon(0% 0%,100% 0%,100% 100%,0% 100%,${ribbonNotch}px 50%)`
                :              `polygon(0% 0%,100% 0%,calc(100% - ${ribbonNotch}px) 50%,100% 100%,0% 100%)`;
            let bgEl = el.querySelector(':scope > .ribbon-bg-layer');
            if (!bgEl) { bgEl = document.createElement('div'); bgEl.className = 'ribbon-bg-layer'; el.insertBefore(bgEl, el.firstChild); }
            bgEl.style.cssText = [
                `position:absolute;inset:0;`,
                fillCss,
                shadows.length ? `box-shadow:${shadows.join(',')};` : '',
                border.width > 0 ? `border:${border.width}px solid ${border.color || '#fff'};` : '',
                `clip-path:${clipPoly};`,
            ].join('');
        } else {
            const oldBg = el.querySelector(':scope > .ribbon-bg-layer');
            if (oldBg) oldBg.remove();
            const maskCss = mask.enabled ? ringMaskCss(mask.innerPct, mask.outerPct) : '';
            el.style.cssText = [
                `position:relative;display:flex;align-items:center;justify-content:center;flex-shrink:0;box-sizing:border-box;`,
                `width:${w}px;height:${h}px;border-radius:${radiusCss};${fillCss}`,
                `box-shadow:${shadows.join(',') || 'none'};`,
                border.width > 0 ? `border:${border.width}px solid ${border.color || '#fff'};` : '',
                maskCss ? `-webkit-mask-image:${maskCss};mask-image:${maskCss};` : '',
            ].join('');
        }

        // bevel 평탄면(child div, ribbon-bg-layer 와 동일 패턴) — 일반 도형 전용.
        // 텍스트/이미지(absolute)는 DOM 뒤 순서라 면 위에 그려진다. ribbon/hollow 전환 시 잔존분 제거.
        const bevel = (!isHollow && !isClipped) ? (model.bevel || {}) : {};
        const oldFace = el.querySelector(':scope > .bevel-face-layer');
        if (bevel.enabled) {
            const faceEl = oldFace || document.createElement('div');
            if (!oldFace) { faceEl.className = 'bevel-face-layer'; el.insertBefore(faceEl, el.firstChild); }
            const fr = Math.max(0, radius - (bevel.side ?? 8));
            const soft = bevel.softness ?? 6;
            faceEl.style.cssText = [
                `position:absolute;pointer-events:none;`,
                `top:${bevel.top ?? 7}px;left:${bevel.side ?? 8}px;right:${bevel.side ?? 8}px;bottom:${bevel.bottom ?? 12}px;`,
                `border-radius:${isTopRoundRect ? `${fr}px ${fr}px 0 0` : `${fr}px`};`,
                `background:${bevel.color || fill.color1 || '#4a90d9'};`,
                soft > 0 ? `box-shadow:0 ${Math.max(1, Math.round(soft / 2))}px ${soft}px ${hexToRgba('#000000', 30)};` : '',
            ].join('');
        } else if (oldFace) {
            oldFace.remove();
        }

        // spin animation: 모든 shape branch 공통. cssText 이후에 추가하여 덮어씌움 방지.
        const cssAnimation = findEffect(effects, 'css-animation');
        const spin = findEffect(effects, 'spin');
        if (spin && spin.enabled && !cssAnimation?.enabled) {
            ensureSpinKeyframes();
            const dur = Math.max(0.001, (spin.timing?.durationMs || 10000) / 1000);
            const name = spin.params?.direction === 'ccw' ? 'ui-spin-rev' : 'ui-spin';
            el.style.animation = `${name} ${dur}s linear infinite`;
            el.style.transformOrigin = '50% 50%';
        } else {
            el.style.animation = '';
        }
        const press = findEffect(effects, 'press');
        const depth = modelShadow(model, 'depth-edge');
        applyPressEffect(el, press, {
            depthPx: press?.params?.useDepthOffset ? (depth.size || 0) : 0,
            normalShadow: el.style.boxShadow,
            pressedShadow: pressedComponentShadowCss(model),
            bevelPress: bevel.enabled ? { top: bevel.top ?? 7, bottom: bevel.bottom ?? 12 } : null,
        });
        applyCssAnimationEffect(el, cssAnimation);
        playParticleEffect(el, findEffect(effects, 'particle-effect'));

        // shine sweep — 도형 실루엣대로 잘리는 광채 오버레이.
        // 일반 도형=el border-radius 클리핑, ribbon/notch=clip-path 를 가진 .ribbon-bg-layer 안에 삽입.
        const shine = findEffect(effects, 'shine');
        const staleShine = el.querySelector(':scope > .ui-shine-overlay');   // 도형 전환(rect↔ribbon) 시 잔존분 제거
        if (staleShine) staleShine.remove();
        if (isClipped) {
            const bgHost = el.querySelector(':scope > .ribbon-bg-layer');
            if (bgHost) applyShineEffect(bgHost, shine, {});
        } else {
            applyShineEffect(el, shine, { borderRadius: radiusCss });
        }
    }

    _textCss(t, sx = 1, sy = 1, objW = 0) {
        const zi = t.zIndex != null ? `z-index:${t.zIndex};` : '';
        const ox = Math.round((t.offsetX || 0) * sx);
        const oy = Math.round((t.offsetY || 0) * sy);
        // white-space:pre = 수동 줄바꿈(\n)만 반영. autoWrap 이면 오브젝트 폭(objW, 이미 스케일된 px)
        // 기준으로 접는다. abs-pos 중앙정렬의 shrink-to-fit 조기 줄바꿈을
        // 피하려고 width:max-content + max-width 조합을 쓴다.
        // 정렬 기준 박스 = 소속 오브젝트 폭. 글자에 딱 맞는(shrink-to-fit) 박스를 쓰면 가장 긴 줄이
        // 박스를 꽉 채워 늘 가운데로 보이고 나머지 줄만 정렬돼 기준이 두 개가 된다 — 오브젝트 폭으로
        // 고정해 모든 줄이 같은 좌우 경계에 맞는다. objW 를 모르는 경로만 종전 shrink-to-fit 폴백.
        const boxW = Math.round(objW || 0);
        // 미지정 텍스트는 가운데 — 종전에도 박스가 앵커에 중앙 정렬돼 한 줄·최장 줄이 가운데였다(표시 불변).
        const align = t.textAlign || 'center';
        const wrap = t.autoWrap && !isTextCurved(t) && boxW > 0;
        const ws = (wrap ? 'white-space:pre-wrap;overflow-wrap:break-word;' : 'white-space:pre;')
            + (boxW > 0 ? `width:${boxW}px;` : '')
            + `text-align:${align};`;
        return `position:absolute;${ws}pointer-events:none;line-height:1.2;${textAppearanceCss(t, sx)}left:calc(50% + ${ox}px);top:calc(50% + ${oy}px);transform:translate(-50%,-50%);${zi}`;
    }

    _applyBackground(el, bg) {
        if (!bg) return;
        // 이전 호출 잔류 제거: scroll 클래스/animation 항상 초기화 후 필요시 다시 부여
        if (el.classList) el.classList.remove('sr-bg-scroll');
        el.style.animation = '';
        // 비동기 합성 콜백 stale-guard 용 stamp 매 호출 무효화 (tile/brick 분기에서 applyPatternFill 이 새 값 부여)
        if (el.dataset) el.dataset.patStamp = '';
        if (bg.type === 'none') { el.style.background = 'transparent'; el.style.backgroundImage = 'none'; return; }
        if (bg.type === 'solid') el.style.background = bg.color || '#16213e';
        else if (bg.type === 'linear-gradient') el.style.background = `linear-gradient(${bg.gradientAngle || 180}deg,${bg.color},${bg.color2})`;
        else if (bg.type === 'image-tile' || bg.type === 'image-brick') {
            // tile/brick 채움+스크롤은 마스크 자식과 공용 헬퍼 단일 소스. brick=tileSize 를 벽돌 높이로, tile=정사각 셀.
            // imagePaths(추가 이미지) 는 imagePath 와 함께 고루 섞어 합성. tilePad=셀 간 여백, imageAlpha=0~100 불투명도.
            const size = bg.tileSize || 64;
            const urls = [bg.imagePath, ...(bg.imagePaths || [])].map(p => this._resolveAssetPath(p)).filter(Boolean);
            const pad = Math.max(0, Math.round(bg.tilePad || 0));
            const alpha = Math.max(0, Math.min(1, (bg.imageAlpha ?? 100) / 100));
            const scroll = bg.scrollEnabled ? { enabled: true, direction: bg.scrollDirection, secPerTile: bg.scrollDuration, epoch: bg.scrollEpoch } : null;
            applyPatternFill(el, {
                imageUrls: urls,
                mode: bg.type === 'image-brick' ? 'brick' : 'tile',
                cellW: size, cellH: size,
                pad, alpha,
                color: bg.color || (bg.type === 'image-brick' ? '#16213e' : ''),
                scroll,
                stamp: `${bg.type}|${urls.join(',')}|${size}|${pad}|${alpha}`,
            });
        }
        else if (bg.type === 'image-stretch') { el.style.background = `${bg.color} url('${this._resolveAssetPath(bg.imagePath)}') no-repeat center`; el.style.backgroundSize = bg.stretchMode || 'cover'; }
    }

    _injectCSS(_scrollMode = false) {
        if (this._styleEl) return;
        // 사일런스 스크롤바 (WebKit) — 일반/nav 양쪽 모두 적용
        const css = `.sr-scroll-inner::-webkit-scrollbar { display:none; }\n`;
        const style = document.createElement('style');
        style.textContent = css;
        document.head.appendChild(style);
        this._styleEl = style;
    }

    /** basePath를 이미지 경로에 붙임. data: URL이나 절대 URL은 건드리지 않음. */
    _resolveAssetPath(path) {
        if (!path || !this._basePath) return path;
        if (path.startsWith('data:') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/')) return path;
        return this._basePath.replace(/\/?$/, '/') + path;
    }

    _flattenPaths(obj, prefix = '') {
        const result = {};
        for (const [k, v] of Object.entries(obj)) {
            const path = prefix ? `${prefix}.${k}` : k;
            if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
                Object.assign(result, this._flattenPaths(v, path));
            } else {
                result[path] = v;
            }
        }
        return result;
    }
}

// ── Public Utils ──────────────────────────────────────────────────────────────
// ui-editor.html 에서 직접 참조할 수 있도록 렌더링 유틸리티를 공개 API로 노출.
// scene-renderer.js = 렌더링 로직의 단일 소스 (Single Source of Truth).
// 캐릭터 정의 캐시 — id → 계약 객체. 게임은 characters/<id>.character.json 을 fetch 해 채우고,
// 에디터는 자기 소스에서 만든 계약을 미리 넣어 둔다(fetch 없이 즉시 조립 미리보기).
SceneRenderer.characterDefs = Object.create(null);
SceneRenderer._characterLoads = Object.create(null);  // 인플라이트 fetch 공유(중복 요청 방지)
// 캐릭터 정의(characters/*.character.json)를 찾는 기준 폴더 = publish 출력 폴더(scene-renderer.js 옆).
// 에셋 기준(SceneRenderer 인스턴스의 basePath)과 별개다 — 이미지 exportPath 는 프로젝트 루트 기준이라
// 하나의 값으로 둘 다 담을 수 없다. 씬 안 캐릭터도 이 값을 쓰므로 게임 부팅 시 한 번 지정한다.
SceneRenderer.characterBase = '';

// 씬 없이 캐릭터 하나만 붙인다(인게임용) — 씬 레이어와 같은 조립·같은 핸들을 그대로 쓴다.
// opts: { defBase: 'src/js' (characters/ 가 있는 폴더 — 생략 시 SceneRenderer.characterBase),
//         basePath: '' (이미지 exportPath 기준 = 씬 렌더러와 동일),
//         equip: {socketId: partId} }
// 반환 = __uiCharacter 핸들 { equip, play, stop, getEquip }
SceneRenderer.mountCharacter = function (hostEl, characterId, opts) {
    const o = opts || {};
    if (o.defBase !== undefined) SceneRenderer.characterBase = o.defBase;
    const el = new SceneRenderer(null, { basePath: o.basePath || '' })
        .buildVisual({ layerType: 'character', characterId, equip: o.equip || {} });
    hostEl.appendChild(el);
    return el.__uiCharacter;
};

// ── 전역 이펙트(씬 밖 스프라이트) ────────────────────────────────────────────
// 씬 레이어가 아닌 이펙트(캐릭터 공격·타격점·스킬 연출)는 씬 json 에서 꺼낼 수 없으므로
// 발행된 effects.json(전역 이펙트 맵)에서 id 로 정의를 찾는다. 재생은 씬 안 스프라이트 레이어와
// 완전히 같은 _buildSpriteVisual/_runSpriteLoop 을 그대로 쓴다(재생 코드 이원화 금지).
// 정의 기준 폴더는 캐릭터와 같은 publish 출력 폴더라 characterBase 를 공유한다(기준값 1개 유지).
SceneRenderer.effectDefs = null;        // effects.json 의 effects 맵(1회 로드 캐시)
SceneRenderer._effectDefsLoad = null;   // 인플라이트 fetch 공유(중복 요청 방지)

SceneRenderer.loadEffectDefs = function (defBase) {
    if (defBase !== undefined) SceneRenderer.characterBase = defBase;
    if (SceneRenderer.effectDefs) return Promise.resolve(SceneRenderer.effectDefs);
    if (SceneRenderer._effectDefsLoad) return SceneRenderer._effectDefsLoad;
    const base = SceneRenderer.characterBase;
    const url = (base ? base.replace(/\/?$/, '/') : '') + 'effects.json';
    SceneRenderer._effectDefsLoad = fetch(url)
        .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(doc => (SceneRenderer.effectDefs = (doc && doc.effects) || {}))
        .catch(e => {
            console.error('[SceneRenderer] 이펙트 정의 로드 실패 — mountSprite 가 동작하지 않습니다:', url, e);
            return null;
        })
        .finally(() => { SceneRenderer._effectDefsLoad = null; });
    return SceneRenderer._effectDefsLoad;
};

// 스프라이트 1회 재생 길이(ms). _runSpriteLoop 의 프레임 지연 규칙(delays 우선, 없으면 fps)과 동일 계산.
function spriteClipDurationMs(clip) {
    const count = Math.max(1, clip.count || (Array.isArray(clip.delays) ? clip.delays.length : 1));
    const defDelay = Math.max(1, Math.round(1000 / (clip.fps || 10)));
    if (Array.isArray(clip.delays) && clip.delays.length)
        return clip.delays.slice(0, count).reduce((a, d) => a + (d || defDelay), 0);
    return count * defDelay;
}

// 씬 없이 이펙트 하나를 재생한다(인게임용). hostEl 안에 붙고, x/y 를 주면 그 좌표(호스트 기준 px)에
// 이펙트 중심을 맞춰 절대배치한다 — 타격점 표시가 기본 용도.
// opts: { defBase: 'src/js' (effects.json 이 있는 발행 폴더 — 생략 시 characterBase),
//         basePath: '' (아틀라스 exportPath 기준 = 씬 렌더러와 동일),
//         x, y, loop(기본 1회, 0=무한), rate(재생속도), startDelayMs, width, height,
//         removeOnEnd(기본 true — 유한 루프가 끝나면 스스로 제거) }
// 반환 Promise<HTMLElement|null> — 정의를 못 찾으면 null(원인은 콘솔).
SceneRenderer.mountSprite = async function (hostEl, effectId, opts) {
    const o = opts || {};
    const defs = await SceneRenderer.loadEffectDefs(o.defBase);
    const def = defs && defs[effectId];
    if (!def) {
        console.error('[SceneRenderer] 이펙트 정의 없음:', effectId,
            '— 등록된 id:', defs ? Object.keys(defs) : '(effects.json 로드 실패)');
        return null;
    }
    // 정의(격자·프레임 지연)는 effects.json, 인스턴스 값(루프/속도/지연)은 호출측 — 씬 레이어와 같은 분담.
    const loop = o.loop !== undefined ? o.loop : 1;
    const clip = Object.assign({}, def.clip, { loop },
        o.rate != null ? { playbackRate: o.rate } : null,
        o.startDelayMs != null ? { startDelayMs: o.startDelayMs } : null);
    const el = new SceneRenderer(null, { basePath: o.basePath || '' }).buildVisual({
        layerType: 'sprite',
        exportPath: def.exportPath,
        clip,
        visual: { width: o.width || clip.cellW || 64, height: o.height || clip.cellH || 64 },
    });
    if (o.x != null || o.y != null) {
        el.style.position = 'absolute';
        el.style.left = (o.x || 0) + 'px';
        el.style.top  = (o.y || 0) + 'px';
        el.style.transform = 'translate(-50%,-50%)'; // 좌표 = 이펙트 중심(타격점)
        el.style.pointerEvents = 'none';
    }
    hostEl.appendChild(el);
    // 1회성 이펙트는 끝나면 스스로 사라진다 — 호출측이 정리 코드를 쓰지 않게. 무한 루프(0)/정지(rate 0)는 유지.
    const rate = clip.playbackRate != null ? clip.playbackRate : 1;
    if (loop > 0 && rate > 0 && o.removeOnEnd !== false) {
        const total = (clip.startDelayMs || 0) + spriteClipDurationMs(clip) * loop / rate;
        setTimeout(() => el.remove(), total + 50); // 마지막 프레임이 그려질 여유
    }
    return el;
};

SceneRenderer.utils = {
    /** depth-gradient CSS 문자열 생성 */
    depthGradientCss,
    /** 회전 레이용 conic-gradient CSS */
    conicRaysCss,
    /** 링 형태 페이드 mask CSS */
    ringMaskCss,
    /** 컴포넌트 fill → CSS 선언문 (solid/gradient/depth/conic/texture 공용 단일 소스) */
    componentFillCss,
    /** 9-slice 기하 계산(모서리 px·클램프·중앙 붕괴 판정) 단일 소스 — 편집기 경고/권장값 공용 */
    sliceGeometry,
    /** 9-slice 붕괴 사유 문자열 배열 */
    sliceCollapseReasons,
    /** 중앙이 붕괴하지 않는 sliceScale 권장값 */
    sliceFitScale,
    /** 텍스처 패턴 목록 [{id,label}] — 에디터 드롭다운용 */
    texturePatterns: TEXTURE_PATTERNS,
    /** 텍스처 id → 에셋 경로 (texture/<id>_large.webp) */
    textureAssetPath,
    /** 위젯(표시/토글/슬라이더) contract 방출 판정 — 완성 시 위젯 객체, 미완성 null (에디터 _mapGroups 공용) */
    widgetContractValue,
    /** navigation 씬 데이터 → 계약 nav 전용 필드 (에디터 buildSceneContract·스토어 프리뷰 공용) */
    navSceneContractFields,
    /** 캐릭터 소켓 변환(로컬↔절대) — v1 캐릭터 파일을 v2(절대 좌표)로 굽는 마이그레이션 전용 */
    applySocketTransform,
    /** 계약 레이어의 배율 포함 bounds — 소켓 변환 입력 */
    contractLayerBounds,
    /** 캐릭터 프레임 클립 길이(마지막 프레임 시각) */
    characterClipDuration,
    /** 캐릭터 프레임 클립 샘플링 — t(ms) 시점의 포즈 맵 { 포즈키: 트랜스폼 } (에디터 미리보기 공용) */
    sampleCharacterClip,
    /** 투사체 조준선 → { x, y, angleDeg } (client 좌표) — 포즈 컨테이너에서 발사 지점·각도 측정 */
    characterAimWorld,
    /** ui-spin keyframes 1회 주입 */
    ensureSpinKeyframes,
    /** confetti keyframes 1회 주입 */
    ensureConfettiKeyframes,
    /** confetti 파티클을 컨테이너에 spawn (에디터 미리보기 버튼에서 직접 호출) */
    spawnConfettiParticles,
    runConfettiPlayback,
    /** 컴포넌트 엘리먼트에 visual 스타일 적용 (texts/images 처리 제외) */
    applyComponentVisual(el, visual) {
        SceneRenderer.prototype._applyComponentVisual.call(null, el, visual);
    },
    /**
     * 씬 배경 스타일 적용 (contract bg 형식: type, color, color2, gradientAngle, imagePath, tileSize, stretchMode)
     * @param {function} [resolveAsset] - 이미지 경로 변환 함수 (기본값: 항등함수)
     */
    applyBackground(el, bg, resolveAsset) {
        const ctx = {
            _resolveAssetPath: resolveAsset || ((p) => p),
        };
        SceneRenderer.prototype._applyBackground.call(ctx, el, bg);
    },
    /** 텍스트 슬롯 CSS 문자열 반환. objW = autoWrap 기준이 되는 소속 오브젝트 폭(px) */
    textCss(t, objW = 0) {
        return SceneRenderer.prototype._textCss.call(null, t, 1, 1, objW);
    },
    /** 워드아트 곡선 배치 적용(에디터 캔버스 등 textCss 단독 경로용). 곡선이면 true. */
    applyTextCurve,
    /** 텍스트 채움 그라데이션 ::after 오버레이 적용(textCss 단독 경로용). 적용되면 true. */
    applyTextGradientOverlay,
    /** 텍스트 text-shadow 값 단일 소스 (CSS export 등 외부 호출용) */
    textShadowValue: buildTextShadowValue,
    normalizeComponentVisualModel,
    normalizeTextStyleModel,
    normalizeImageStyleModel,
    imageShadowCss,
    imageTintFilterCss,
    findEffect,
    componentShadowCss,
    pressedComponentShadowCss,
    pressFallbackDepthPx: PRESS_FALLBACK_DEPTH_PX,
    cssAnimationPresets: CSS_ANIMATION_PRESETS,
    particleEffectPresets: PARTICLE_EFFECT_PRESETS,
    // 외부(에디터 CSS export 등)에는 종전대로 provider → URL 맵을 노출한다. export 산출물은 게임 밖에서도 열리므로 CDN URL 이 맞다.
    cssEffectProviderStyles: Object.fromEntries(Object.entries(CSS_EFFECT_PROVIDER_STYLES).map(([k, v]) => [k, v.cdn])),
    effectProviderScripts: Object.fromEntries(Object.entries(EFFECT_PROVIDER_SCRIPTS).map(([k, v]) => [k, v.cdn])),
    normalizeCssAnimationEffect,
    applyCssAnimationEffect,
    /** 동적 탭바 — 설정 정규화 + DOM 빌더 (에디터 캔버스 미리보기 공유용) */
    normalizeNavTabBar,
    buildNavTabBar,
    buildNavBgEl,
    normalizeParticleEffect,
    applyAmbientSparkleAura,
    applyHealingAura,
    playParticleEffect,
    /** 광채 스윕(shine sweep) — 정규화/적용 (컴포넌트·이미지 공용 단일 소스) */
    normalizeShineEffect,
    applyShineEffect,
    /** 오브젝트 마스크 — 부모 실루엣 클리핑 평면 빌더 + 계약 레이어 bounds (에디터 캔버스 공유) */
    buildMaskClipPlane,
    contractLayerBounds,
    /** 마스크 자식 흐름 — 정규화/통과 이동/타일 무한 스크롤 (에디터 캔버스 공유) */
    normalizeMaskFlowCfg,
    applyMaskFlow,
    buildMaskFlowTileEl,
    /** 반복 패턴 채움/스크롤 — 배경 image-tile/brick 과 마스크 Tile/Brick 공용 단일 소스 */
    applyPatternFill,
    applyPatternScroll,
    /**
     * 저장된 컴포넌트/그룹 데이터 → 미리보기용 씬 객체 변환 (canvasWidth/canvasHeight/layers).
     * 그룹 템플릿(x_rel 포함)과 단일 컴포넌트 state를 모두 처리하며, 그룹 내부의 zIndex 순서를 보존한다.
     * @param {object} data - 그룹 템플릿({layers:[{x_rel,y_rel,zIndex,...}]}) 또는 단일 컴포넌트 state
     * @param {object} [opts] - { pad?: number }
     */
    componentDataToScene(data, opts) {
        const PAD = (opts && opts.pad != null) ? opts.pad : 16;
        if (Array.isArray(data.layers) && 'x_rel' in (data.layers[0] || {})) {
            let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
            for (const l of data.layers) {
                const cs = l.componentState;
                const w = cs ? (cs.shapeType === 'circle' ? Math.max(cs.width, cs.height) : cs.width) : (l.width || 60);
                const h = cs ? (cs.shapeType === 'circle' ? Math.max(cs.width, cs.height) : cs.height) : (l.height || 40);
                minX = Math.min(minX, l.x_rel || 0); minY = Math.min(minY, l.y_rel || 0);
                maxX = Math.max(maxX, (l.x_rel || 0) + w); maxY = Math.max(maxY, (l.y_rel || 0) + h);
            }
            return {
                canvasWidth: Math.max(maxX - minX + PAD * 2, 80),
                canvasHeight: Math.max(maxY - minY + PAD * 2, 40),
                bgType: 'none', name: data.name,
                layers: data.layers.map((l, i) => ({
                    ...l, id: i + 1,
                    x: (l.x_rel || 0) - minX + PAD,
                    y: (l.y_rel || 0) - minY + PAD,
                    zIndex: l.zIndex != null ? l.zIndex : (i + 1),
                    visible: true, tabIds: [], events: [],
                })),
            };
        }
        const cw = data.shapeType === 'circle' ? Math.max(data.width || 120, data.height || 48) : (data.width || 120);
        const ch = data.shapeType === 'circle' ? Math.max(data.width || 120, data.height || 48) : (data.height || 48);
        return {
            canvasWidth: cw + PAD * 2, canvasHeight: ch + PAD * 2, bgType: 'none', name: data.name,
            layers: [{
                id: 1, type: 'component', name: data.name || 'Component',
                componentState: data,
                x: PAD, y: PAD, scale: 1, scaleX: 1, scaleY: 1,
                zIndex: 1, visible: true, tabIds: [], events: [],
            }],
        };
    },

    /**
     * 에디터 레이어 + 해석된 컴포넌트 state → contract 레이어 변환
     * @param {object} layer  - 에디터 씬 레이어 객체
     * @param {object|null} cs - 해석된 componentState (호출자가 전달)
     */
    layerToContractLayer(layer, cs) {
        const slug = s => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'layer';
        const stableId = layer.stableId || (slug(cs ? cs.name : (layer.name || 'layer')) + '-' + (layer.id || Math.random().toString(36).slice(2)));
        const visual = cs
            ? (({ texts: _t, selectedTextIndex: _i, selectedImageIndex: _ii, name: _n, ...v }) => v)(cs)
            : { exportPath: layer.exportPath || '', width: layer.width || 64, height: layer.height || 64 };
        const textSrc = layer.type === 'image' ? (layer.texts || []) : (cs ? cs.texts || [] : []);
        // confetti 레이어는 visual 에 width/height + confetti 옵션을 묶어 전달
        const isConfetti = layer.type === 'confetti';
        const isSprite = layer.type === 'sprite';
        const normalizedComponent = layer.type === 'component' ? normalizeComponentVisualModel(visual) : null;
        const normalizedImageStyle = layer.type === 'image' ? normalizeImageStyleModel(layer) : null;
        const confettiVisual = isConfetti ? {
            width: layer.width || 320, height: layer.height || 240,
            confetti: {
                confettiPattern: layer.confettiPattern || 'center-burst',
                particleCount: layer.particleCount,
                duration: layer.duration,
                spread: layer.spread, velocity: layer.velocity,
                colors: layer.colors, sizeMin: layer.sizeMin, sizeMax: layer.sizeMax,
                shape: layer.shape,
                autoplay: layer.autoplay !== false,
                loop: !!layer.loop,
                repeat: layer.repeat,
                loopDelay: layer.loopDelay,
                triggerKey: layer.triggerKey || '',
            },
        } : null;
        const contractVisual = isConfetti ? confettiVisual
            : layer.type === 'character' ? {
                // 캐릭터 인스턴스는 조립 정보를 갖지 않는다 — 박스 크기만 싣고 정의는 characterId 로 참조.
                width: layer.width || 0,
                height: layer.height || 0,
            }
            : isSprite ? {
                exportPath: layer.exportPath || '',
                width: layer.width || (layer.clip && layer.clip.cellW) || 64,
                height: layer.height || (layer.clip && layer.clip.cellH) || 64,
                clip: layer.clip || null,
            }
            : layer.type === 'component' ? {
                model: normalizedComponent.visualModel,
                images: (visual.images || []).map(im => ({
                    exportPath: im.exportPath || '',
                    imageKey: im.imageKey || '',
                    width: im.width || 32,
                    height: im.height || 32,
                    offsetX: im.offsetX || 0,
                    offsetY: im.offsetY || 0,
                    zIndex: im.zIndex,
                    style: normalizeImageStyleModel(im),
                })),
            }
            : {
                exportPath: layer.exportPath || '',
                width: layer.width || 64,
                height: layer.height || 64,
                style: normalizedImageStyle,
            };
        let effects = isConfetti ? [{
            type: 'confetti',
            source: { provider: 'internal', name: 'confetti' },
            enabled: true,
            target: 'self',
            trigger: layer.triggerKey ? 'manual' : 'mount',
            params: {
                pattern: layer.confettiPattern || 'center-burst',
                particleCount: layer.particleCount,
                durationMs: layer.duration,
                spread: layer.spread,
                velocity: layer.velocity,
                colors: layer.colors,
                sizeMin: layer.sizeMin,
                sizeMax: layer.sizeMax,
                shape: layer.shape,
                autoplay: layer.autoplay !== false,
                loop: !!layer.loop,
                repeat: layer.repeat,
                loopDelay: layer.loopDelay,
                triggerKey: layer.triggerKey || '',
            },
        }] : layer.type === 'component' ? normalizedComponent.effects
            : layer.type === 'image' ? [normalizePressEffect(layer), normalizeCssAnimationEffect(layer), normalizeParticleEffect(layer), normalizeShineEffect(layer)]
            : [];
        if (!isConfetti) effects = effects.filter(effect => effect?.enabled !== false);
        const contractLayer = {
            stableId,
            layerType: layer.type,
            displayName: cs ? cs.name : (layer.name || ''),
            x: layer.x || 0, y: layer.y || 0,
            scale: layer.scale || 1, scaleX: layer.scaleX ?? 1, scaleY: layer.scaleY ?? 1,
            zIndex: layer.zIndex || 1, visible: layer.visible !== false,
            // 위젯(표시/토글/슬라이더) — 완성된 선언만 방출 (visibleBindingKey 를 흡수한 통합 바인딩)
            ...(widgetContractValue(layer.widget) ? { widget: layer.widget } : {}),
            tabIds: layer.tabIds || [], navTabId: layer.navTabId || null, targetTabId: layer.targetTabId || null,
            visual: contractVisual,
            effects,
            texts: textSrc.map((t, i) => ({
                slotIndex: i, staticContent: t.content || '', bindingKey: t.bindingKey || '',
                fontSize: t.fontSize, fontWeight: t.fontWeight, fontFamily: t.fontFamily || 'inherit',
                color: t.color,
                offsetX: t.offsetX, offsetY: t.offsetY, zIndex: t.zIndex,
                style: normalizeTextStyleModel(t),
                ...(t.curveType === 'arc' ? { curveType: 'arc', curveAngle: t.curveAngle || 0 } : {}),
                ...(t.autoWrap ? { autoWrap: true } : {}),
                ...(t.textAlign ? { textAlign: t.textAlign } : {}),
            })),
            image: layer.type === 'image' ? { exportPath: layer.exportPath || '', imageKey: layer.imageKey || '', style: normalizedImageStyle } : null,
            // 스크롤 고정(핀) — 스크롤 씬에서 스크롤 밖에 붙어 화면에 고정 (그룹 scrollFixed 와 같은 규약)
            ...(layer.scrollFixed ? { scrollFixed: true } : {}),
            // 오브젝트 마스크 — 자식: 부모 stableId 참조 / 부모: 스텐실 전용(그래픽 숨김) 플래그 / 자식 흐름 설정
            ...(layer.maskParentId ? { maskParentId: layer.maskParentId } : {}),
            ...(layer.maskShowGraphic === false ? { maskShowGraphic: false } : {}),
            ...(layer.maskParentId && (layer.maskFlow?.enabled || layer.maskFlow?.tiled) ? { maskFlow: layer.maskFlow } : {}),
            // 캐릭터 인스턴스 — 조립 정의 참조 + 이 씬에서의 장착 오버라이드(무기 교체)
            ...(layer.type === 'character' ? {
                characterId: layer.characterId || '',
                equip: layer.equip || {},
            } : {}),
            rotation: layer.rotation || 0,
            flipX: !!layer.flipX, flipY: !!layer.flipY,
            events: (layer.events || []).map(ev => ({
                trigger: ev.trigger,
                eventName: ev.eventName || (stableId + ':' + (ev.trigger || 'click')),
                // 게임 동작 메모 — 씬 이동 없는 동작 선언(예: "클릭시 40코인 소모하고 재도전 기회 부여").
                // 에디터/렌더러는 해석하지 않고 게임 개발 AI 가 읽는 문서 필드.
                ...(ev.memo ? { memo: ev.memo } : {}),
                ...(ev.targetSceneUuid ? { targetSceneUuid: ev.targetSceneUuid } : {}),
                // 조건 분기(같은 버튼이 조건에 따라 다른 씬으로) — condition 은 게임이 판정하는 선언용 키,
                // 위에서부터 평가하고 'else' 가 기본 분기. 에디터/렌더러는 의미를 해석하지 않는다.
                ...(Array.isArray(ev.branches) && ev.branches.length ? {
                    branches: ev.branches.map(b => ({
                        condition: b.condition || 'else',
                        targetSceneUuid: b.targetSceneUuid || null,
                        targetSceneName: b.targetSceneName || '',
                    })),
                } : {}),
            })),
        };
        if (contractLayer.scale === 1) delete contractLayer.scale;
        if (contractLayer.scaleX === 1) delete contractLayer.scaleX;
        if (contractLayer.scaleY === 1) delete contractLayer.scaleY;
        if (contractLayer.visible === true) delete contractLayer.visible;
        if (!contractLayer.tabIds.length) delete contractLayer.tabIds;
        if (!contractLayer.navTabId) delete contractLayer.navTabId;
        if (!contractLayer.targetTabId) delete contractLayer.targetTabId;
        if (!contractLayer.effects.length) delete contractLayer.effects;
        if (!contractLayer.texts.length) delete contractLayer.texts;
        if (Array.isArray(contractLayer.visual?.images)) {
            contractLayer.visual.images.forEach(im => {
                if (!im.imageKey) delete im.imageKey;
                if (isDefaultImageStyle(im.style)) delete im.style;
            });
            if (!contractLayer.visual.images.length) delete contractLayer.visual.images;
        }
        if (isDefaultImageStyle(contractLayer.visual?.style)) delete contractLayer.visual.style;
        if (isDefaultImageStyle(contractLayer.image?.style)) delete contractLayer.image.style;
        if (contractLayer.image && !contractLayer.image.imageKey) delete contractLayer.image;
        if (contractLayer.image === null) delete contractLayer.image;
        if (contractLayer.rotation === 0) delete contractLayer.rotation;
        if (!contractLayer.flipX) delete contractLayer.flipX;
        if (!contractLayer.flipY) delete contractLayer.flipY;
        if (!contractLayer.events.length) delete contractLayer.events;
        return contractLayer;
    },
};

// <script type="module" src="scene-renderer.js"> 로 로드 시 전역 접근 가능하도록 노출
if (typeof window !== 'undefined') window.SceneRenderer = SceneRenderer;

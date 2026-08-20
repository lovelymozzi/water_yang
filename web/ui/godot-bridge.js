// ui-editor 런타임 — publish마다 이 파일이 게임 출력 폴더에 덮어써진다. 게임에서 수정 금지(읽기 전용).
// godot-bridge — Godot 웹 익스포트를 game-session.js 카트리지 계약에 맞추는 어댑터.
//
// ── 프로토콜 정본 (JS 호스트 ↔ GDScript ui_bridge.gd) ────────────────────────
// 핸드셰이크 순서:
//   1. mount(el, session): el 안에 canvas 생성 → window.UiBridge 설치 → engine.js 로드 → Engine 부팅 개시
//   2. GDScript autoload _ready(): JavaScriptBridge.get_interface("UiBridge") → setHandler(cb) → ready()
//   3. initialize(stageData): 부팅 완료 + ready() 대기 → 'initialize' 커맨드 송신 → GDScript 'initialized' 응답 대기
//   4. startGame() 이후 hud/progress/end/error 가 session.post 로 관통
//   5. 종료: end 수신 시 이후 post 전부 드롭. forceQuit 은 end 포함 전부 드롭(계약: forceQuit 에서 end 금지).
//      unmount: engine.requestQuit() → canvas 제거 → window.UiBridge 삭제. 멱등.
//      다음 세션의 엔진 부팅은 이전 엔진의 onExit(WASM 정리 완료)를 기다린다(수명 경합 방지).
//
// 호스트→Godot 커맨드 — setHandler 로 등록된 콜백에 JSON 문자열 1개:
//   JSON.stringify({ v:1, cmd, payload })
//   cmd: initialize {stage,seed,config} | startGame {} | pauseGame {reason} | resumeGame {} | forceQuit {reason}
//        | message {topic, payload}  — GameSession.message() 자유 메시지(설정 변경·구매 결과 등) → GDScript host_message 시그널
//
// Godot→호스트 — window.UiBridge.post(type, jsonString):
//   내부 소비: 'initialized' {} (ready 는 UiBridge.ready() 메서드 호출)
//   관통: 'hud' | 'progress' | 'end' {outcome,score,stats?} | 'error' {message}  — game-session.js CARTRIDGE_EVENTS 그대로
//   화이트리스트 밖 type·JSON 파싱 실패는 드롭 + console.warn
//
// 페이로드는 양방향 전부 JSON 문자열 — Godot↔JS 객체 마샬링 함정 회피,
// JSON.parse 결과는 항상 plain object 라 game-session.js 의 assertSerializable 을 통과한다.
//
// 전역 사용은 2개뿐(ingame 스킬 금지 규칙의 명시적 예외): window.UiBridge(unmount 시 삭제),
// window.Engine(Godot 익스포트 산출물 자체). Godot 웹 엔진은 페이지당 동시 1개 — 모듈 레벨 락으로 강제.
// 엔진 수명 = 세션 수명(mount 에서 생성, unmount 에서 requestQuit) — 재도전은 start() 재호출로 새 부팅.

export const GODOT_BRIDGE_VERSION = 1;
export const GODOT_INTERFACE_NAME = 'UiBridge';

let _engineScriptP = null; // engine.js(전역 Engine 클래스) 로드는 페이지당 1회 memoize
let _activeLock = false;   // Godot 웹 엔진 동시 1세션 강제
let _prevQuitP = Promise.resolve(); // 직전 엔진의 onExit(WASM 정리 완료) 게이트 — 다음 엔진 부팅은 이걸 기다린다.
//   requestQuit() 은 종료 "요청"일 뿐 완료를 안 알려줘서, 이 게이트 없이는 이전 엔진 teardown 중에
//   새 엔진이 부팅되는 수명 경합("Object was deleted while awaiting a callback"/WASM OOB)이 난다.

function loadEngineScript(url) {
    if (typeof window.Engine === 'function') return Promise.resolve();
    if (!_engineScriptP) {
        _engineScriptP = new Promise((resolve, reject) => {
            const s = document.createElement('script');
            s.src = url;
            s.onload = () => {
                if (typeof window.Engine === 'function') resolve();
                else reject(new Error(`[godot-bridge] ${url} 로드됐지만 window.Engine 이 없음 — Godot 웹 익스포트 engine.js 인지 확인`));
            };
            s.onerror = () => {
                _engineScriptP = null; // 실패는 memoize 하지 않음 — 재시도 허용
                reject(new Error(`[godot-bridge] engine.js 로드 실패: ${url}`));
            };
            document.head.appendChild(s);
        });
    }
    return _engineScriptP;
}

/**
 * Godot 웹 익스포트를 GameSession 카트리지로 감싸는 팩토리 생성기.
 * @param {object} opts
 * @param {string} opts.engineUrl - Godot 익스포트 engine.js URL (셸 템플릿의 $GODOT_URL)
 * @param {object} opts.engineConfig - Godot 익스포트 설정 (셸 템플릿의 $GODOT_CONFIG — executable·args 등)
 * @param {number} [opts.bootTimeoutMs] - 부팅 후 GDScript ready() 대기 한도 (기본 20000) — 진단 문구용.
 *   전체 예산은 GameSession 의 initTimeoutMs 가 지배하므로 Godot 게임은 initTimeoutMs:30000 권장.
 * @param {object} [opts.configOverrides] - Engine config 추가 필드(canvas·canvasResizePolicy 뒤에 병합)
 * @returns {Function} createCartridge 팩토리 — GameSession.start() 첫 인자로 그대로 전달
 */
export function makeGodotCartridge({ engineUrl, engineConfig, bootTimeoutMs = 20000, configOverrides = null } = {}) {
    if (!engineUrl) throw new Error('[godot-bridge] engineUrl 필수 — 셸 템플릿의 $GODOT_URL');
    return function createCartridge() {
        let engine = null, canvas = null, ro = null, session = null;
        let handler = null;            // GDScript setHandler 콜백 — 커맨드 송신 통로
        let terminating = false;       // forceQuit/unmount 이후 — end 포함 모든 post 드롭
        let ended = false;             // end 1회 수신 이후 — 늦은 post 드롭
        let bootP = null;
        let readyResolve; const readyP = new Promise((r) => { readyResolve = r; });
        let initedResolve; const initedP = new Promise((r) => { initedResolve = r; });
        let quitResolve; const quitP = new Promise((r) => { quitResolve = r; }); // 이 엔진의 onExit 완료

        function sendCommand(cmd, payload = {}) {
            if (!handler) { console.warn('[godot-bridge] 커맨드 드롭(GDScript 핸들러 미등록):', cmd); return; }
            handler(JSON.stringify({ v: GODOT_BRIDGE_VERSION, cmd, payload }));
        }

        function onPost(type, jsonStr) {
            if (terminating || ended) { console.log('[godot-bridge] 늦은 post 드롭(세션 종료 후):', type); return; }
            let payload;
            try { payload = JSON.parse(jsonStr || '{}'); } catch (e) {
                console.warn('[godot-bridge] post 드롭(JSON 파싱 실패):', type, jsonStr); return;
            }
            if (type === 'initialized') { initedResolve(); return; }
            if (type !== 'hud' && type !== 'progress' && type !== 'end' && type !== 'error') {
                console.warn('[godot-bridge] post 드롭(알 수 없는 type):', type); return;
            }
            if (type === 'end') ended = true;
            session.post(type, payload);
        }

        function fitCanvas(el) {
            // canvasResizePolicy:0 — 엔진이 canvas 크기를 만지지 않으므로 브리지가 컨테이너에 맞춘다.
            const dpr = window.devicePixelRatio || 1;
            const w = Math.max(1, Math.round(el.clientWidth * dpr));
            const h = Math.max(1, Math.round(el.clientHeight * dpr));
            if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        }

        return {
            mount(el, sess) {
                if (_activeLock) throw new Error('[godot-bridge] Godot 엔진은 페이지당 동시 1세션만 지원 — 이전 세션 정리(unmount) 후 재시도');
                _activeLock = true;
                session = sess;
                canvas = document.createElement('canvas');
                canvas.id = 'godot-bridge-canvas'; // 필수 — Godot(Emscripten)이 GL 컨텍스트 생성 시 '#'+id 셀렉터로 canvas 를 찾는다(id 없으면 '#' 셀렉터 예외)
                canvas.tabIndex = 0; // 필수 — Godot 은 keydown/keyup 을 canvas 에 건다. tabindex 없으면 포커스 불가 → 키 입력 전달 안 됨(focusCanvas 옵션도 무시됨)
                canvas.style.cssText = 'width:100%;height:100%;display:block;outline:none;';
                el.appendChild(canvas);
                fitCanvas(el);
                ro = new ResizeObserver(() => fitCanvas(el));
                ro.observe(el);
                window[GODOT_INTERFACE_NAME] = {
                    v: GODOT_BRIDGE_VERSION,
                    setHandler(cb) { handler = cb; },
                    ready() { console.log('[godot-bridge] GDScript ready'); readyResolve(); },
                    post: onPost,
                };
                bootP = Promise.all([loadEngineScript(engineUrl), _prevQuitP]).then(() => {
                    if (terminating) return; // 부팅 대기 중 forceQuit/unmount — 엔진 생성 자체를 건너뛴다
                    engine = new window.Engine({ ...engineConfig, canvas, canvasResizePolicy: 0, onExit: () => quitResolve(), ...(configOverrides || {}) });
                    return engine.startGame();
                });
                bootP.catch(() => {}); // 정식 소비는 initialize 의 await — mount 단계 unhandled rejection 방지
            },

            async initialize(stageData) {
                await bootP; // 부트 실패는 여기서 원본 오류로 전파 → GameSession _fail 경로
                await Promise.race([
                    readyP,
                    new Promise((_, rej) => setTimeout(() => rej(new Error(
                        `[godot-bridge] GDScript ready() 미호출(${bootTimeoutMs}ms) — ui_bridge.gd 가 autoload "UiBridge" 로 등록됐는지 확인`)), bootTimeoutMs)),
                ]);
                sendCommand('initialize', stageData);
                await initedP; // GDScript 가 notify_initialized() 를 안 부르면 GameSession initTimeoutMs 가 최종 판정
            },

            startGame() { sendCommand('startGame'); },
            pauseGame(reason) { sendCommand('pauseGame', { reason }); },
            resumeGame() { sendCommand('resumeGame'); },
            onMessage(topic, payload) { sendCommand('message', { topic: topic, payload: payload }); },

            forceQuit(reason) {
                terminating = true; // 이후 GDScript 의 어떤 post 도(end 포함) 드롭 — 계약: forceQuit 에서 end 금지
                sendCommand('forceQuit', { reason });
            },

            unmount() {
                terminating = true;
                if (engine) {
                    try { engine.requestQuit(); } catch (e) {
                        console.error('[godot-bridge] requestQuit 예외(강제 정리로 계속):', e);
                        quitResolve(); // onExit 이 안 올 수 있으므로 게이트 해제 — 다음 부팅 영구대기 방지
                    }
                    _prevQuitP = quitP; // 다음 세션의 엔진 부팅은 이 엔진의 onExit 이후
                }
                engine = null;
                if (ro) { ro.disconnect(); ro = null; }
                if (canvas && canvas.parentNode) canvas.parentNode.removeChild(canvas);
                canvas = null;
                // 이 세션이 설치한 인터페이스만 정리 — 다음 세션이 이미 설치했으면 건드리지 않는다
                if (window[GODOT_INTERFACE_NAME] && window[GODOT_INTERFACE_NAME].post === onPost) delete window[GODOT_INTERFACE_NAME];
                if (_activeLock) _activeLock = false;
            },
        };
    };
}

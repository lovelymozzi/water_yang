extends Node
## ui-editor UiBridge — 웹 호스트(godot-bridge.js) ↔ Godot 게임의 표준 경계.
## 설치: 이 파일을 게임 프로젝트에 복사하고 프로젝트 설정 > Autoload 에 이름 "UiBridge" 로 등록한다.
## 프로토콜 정본은 publish 산출물 godot-bridge.js 상단 주석. 상세는 ui-editor-game 스킬 §5 Godot 절.
##
## 계약 규칙(위반 시 아웃게임이 세션을 강제 정리한다):
##   - host_initialize 처리(스테이지 로드)가 끝나면 반드시 notify_initialized() 를 호출한다
##     — 안 부르면 GameSession initialize 타임아웃으로 세션이 실패한다.
##   - end 는 플레이 1회에 1번만. host_force_quit 이후에는 post_end 를 부르지 않는다
##     (부르더라도 브리지가 드롭하지만, 게임 쪽에서도 호출하지 않는 것이 규약).
##   - hud 필드는 표준 어휘만: score / movesLeft / goal / timeLeft / combo / stage.
##   - 웹이 아니거나(에디터 F5 네이티브 실행) 호스트 없이 열리면 no-op 폴백 — 게임 단독 실행이 보장된다.

signal host_initialize(stage_data: Dictionary)  # {stage, seed, config} — 처리 후 notify_initialized() 의무
signal host_start                               # 플레이 개시(이 전에는 입력을 받지 말 것)
signal host_pause(reason: String)               # 'user' | 'popup' | 'hidden'
signal host_resume
signal host_force_quit(reason: String)          # 리소스 정리. end 를 보내지 말 것
signal host_message(topic: String, payload)     # 호스트 자유 메시지(설정 변경·구매 결과 등, GameSession.message). payload = JSON 값

var is_hosted := false          # true = 웹 호스트(godot-bridge.js) 아래에서 실행 중
var auto_pause := true          # host_pause/resume 에서 get_tree().paused 자동 처리(직접 제어하려면 false)
var standalone_autostart := true # 비호스트 실행 시 디버그 스테이지로 자동 initialize/start 발화
var standalone_stage := {"stage": 1, "seed": 0, "config": {}}

var _iface = null
var _cb = null  # JavaScriptBridge 콜백 참조 — 멤버로 보관하지 않으면 GC 되어 커맨드가 유실된다(필수)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # auto_pause 로 트리가 멈춰도 resume 커맨드를 받아야 한다
	if OS.has_feature("web") and JavaScriptBridge.eval("typeof window.UiBridge !== 'undefined'"):
		# eval 선확인 — 호스트 없이(기본 셸/단독 배포) 실행될 때 get_interface 의 엔진 ERROR 로그를 피한다
		_iface = JavaScriptBridge.get_interface("UiBridge")
	if _iface != null:
		is_hosted = true
		_cb = JavaScriptBridge.create_callback(_on_command)
		_iface.setHandler(_cb)
		_iface.ready()
	elif standalone_autostart:
		_standalone_boot.call_deferred()

## 비호스트(에디터 F5·네이티브) — 다음 프레임에 발화해 메인 씬의 시그널 연결이 끝난 뒤 도착하게 한다.
func _standalone_boot() -> void:
	await get_tree().process_frame
	emit_signal("host_initialize", standalone_stage)
	emit_signal("host_start")

func _on_command(args: Array) -> void:
	var msg = JSON.parse_string(str(args[0]))
	if msg == null or typeof(msg) != TYPE_DICTIONARY:
		push_warning("[UiBridge] 커맨드 파싱 실패: %s" % [args])
		return
	var payload: Dictionary = msg.get("payload", {})
	match msg.get("cmd", ""):
		"initialize":
			emit_signal("host_initialize", payload)
		"startGame":
			emit_signal("host_start")
		"pauseGame":
			if auto_pause: get_tree().paused = true
			emit_signal("host_pause", str(payload.get("reason", "")))
		"resumeGame":
			if auto_pause: get_tree().paused = false
			emit_signal("host_resume")
		"forceQuit":
			emit_signal("host_force_quit", str(payload.get("reason", "")))
		"message":
			emit_signal("host_message", str(payload.get("topic", "")), payload.get("payload"))
		_:
			push_warning("[UiBridge] 알 수 없는 커맨드: %s" % [msg.get("cmd", "")])

# ── 게임 → 호스트 ────────────────────────────────────────────────────────────

## host_initialize 처리 완료 신호 — 스테이지 로드가 끝난 시점에 반드시 1회 호출.
func notify_initialized() -> void:
	_post("initialized", {})

## HUD 값 보고 — 표준 어휘만: {"score": 10, "movesLeft": 5, ...} 부분 갱신 허용.
func post_hud(fields: Dictionary) -> void:
	_post("hud", fields)

## 도메인 진행 이벤트(자유 정의 직렬화 객체).
func post_progress(data: Dictionary) -> void:
	_post("progress", data)

## 종료 보고 — outcome: "clear" | "fail" | "quit". 플레이 1회에 1번만.
func post_end(outcome: String, score: int, stats: Dictionary = {}) -> void:
	_post("end", {"outcome": outcome, "score": score, "stats": stats})

## 복구 불가 오류 자진 보고 — 호스트가 세션을 강제 종료한다.
func post_error(message: String) -> void:
	_post("error", {"message": message})

func _post(type: String, payload: Dictionary) -> void:
	if _iface == null:
		return  # 비호스트 실행 — no-op
	_iface.post(type, JSON.stringify(payload))

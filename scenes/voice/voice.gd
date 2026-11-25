extends Node

## Read the texts of the game aloud, so that the children who can not read yet
## can play, too.
##
## The voices are the ones of the computer (Godot's text-to-speech): Speech
## Dispatcher with eSpeak NG on Linux, the system voices on macOS and Windows.
## They run offline, like the rest of the game. For every language we take
## the voice whose locale matches best the "voice" of the language in
## `res://translations/languages.json` (e.g., "pt_PT", not the Portuguese of
## Brazil); a language without any voice on the computer stays silent.
##
## The scripts say a text with Speech.say, which finds this node. A new text
## interrupts the one being said, except where the caller queues it (e.g., the
## toasts while sailing).
##
## The voice is off until the players switch it on with V; the choice is
## remembered. Start the game with `-- --no-voice` to keep the voice off
## whatever the choice, e.g., for the tests and the renders.

const _SETTINGS_PATH := "user://settings.cfg"

## How fast the voice speaks (1.0 is the voice's normal pace); a little slower,
## for the children.
const RATE := 0.9

## A text said again within this many milliseconds while it is still being
## said (e.g., a hand which wavers at the edge of a button) is not started over.
const _REPEAT_MS := 2000

var _enabled := true

## The voice is off until the players switch it on (see the class).
var _muted := true

## The voice for every language code, once looked up; "" for none.
var _voices := {}

var _last_text := ""
var _last_ms := -_REPEAT_MS


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _enabled = (
        "--no-voice" not in OS.get_cmdline_user_args()
        and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
    )

    var settings := ConfigFile.new()
    if settings.load(_SETTINGS_PATH) == OK:
        _muted = settings.get_value("general", "voice_muted", true)


# NOTE (mristin):
# The voice stops with the game, instead of finishing its sentence.
func _exit_tree() -> void:
    stop()


# NOTE (mristin):
# We listen to the unhandled input (and not to the keys before it), so that the
# keyboard of the captain's name gets a "V" first.
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
        set_muted(not _muted)


func is_muted() -> bool:
    return _muted


func set_muted(muted: bool) -> void:
    _muted = muted
    if muted:
        stop()

    var settings := ConfigFile.new()
    settings.load(_SETTINGS_PATH)
    settings.set_value("general", "voice_muted", muted)
    settings.save(_SETTINGS_PATH)


## Say the text (already translated) in the language of the game, or in the
## language of [param code] (e.g., the names on the language select).
## [param interrupt] stops what is being said; otherwise the text waits its turn.
func say(text: String, interrupt := true, code := "") -> void:
    if not _enabled or _muted:
        return
    var spoken := text.strip_edges()
    if spoken == "":
        return
    if code == "":
        code = _languages().current() if _languages() != null else "en"
    var voice := voice_for(code)
    if voice == "":
        return

    var now := Time.get_ticks_msec()
    if spoken == _last_text and now - _last_ms < _REPEAT_MS and is_speaking():
        return
    _last_text = spoken
    _last_ms = now
    DisplayServer.tts_speak(spoken, voice, 100, 1.0, RATE, 0, interrupt)


## Stop what is being said, and forget what waits its turn.
func stop() -> void:
    if _enabled:
        DisplayServer.tts_stop()


## Whether the voice is saying something now.
func is_speaking() -> bool:
    return _enabled and not _muted and DisplayServer.tts_is_speaking()


## The id of the voice which reads the language of [param code], or "" if the
## computer has none.
func voice_for(code: String) -> String:
    if _voices.has(code):
        return _voices[code]
    var wanted := code
    if _languages() != null:
        wanted = _languages().voice_locale(code)
    var best := best_voice(DisplayServer.tts_get_voices(), code, wanted)
    _voices[code] = best
    return best


## The id of the voice among [param voices] (as DisplayServer.tts_get_voices
## lists them) which reads the language of [param code] best, preferring the
## locale [param wanted] (e.g., "pt_PT"); "" if none speaks the language.
static func best_voice(voices: Array, code: String, wanted: String) -> String:
    var best := ""
    var best_score := -1
    for voice in voices:
        var score := score_voice(voice["language"], voice["name"], code, wanted)
        if score > best_score:
            best = voice["id"]
            best_score = score
    return best


## How well a voice fits the language: -1 if it speaks another one; higher for
## the wanted region (e.g., "PT" of "pt_PT"), then for no region at all, and
## lower for the variants (eSpeak NG on Linux lists, e.g., "German+Andrea" with
## the language "de_Andrea" beside the plain "German" with "de_none").
static func score_voice(language: String, name: String, code: String, wanted: String) -> int:
    var parts := language.replace("-", "_").split("_")
    if parts[0].to_lower() != code:
        return -1
    var wanted_parts := wanted.replace("-", "_").split("_")
    var wanted_region := wanted_parts[1].to_upper() if wanted_parts.size() > 1 else ""

    var region := ""
    var rest := 1
    if parts.size() > 1:
        var candidate := parts[1]
        var is_region := (
            (candidate.length() == 2 and candidate == candidate.to_upper())
            or (candidate.length() == 3 and candidate.is_valid_int())
        )
        if is_region:
            region = candidate
            rest = 2
    var extra := 0
    for i in range(rest, parts.size()):
        if parts[i].to_lower() != "none":
            extra += 1

    var score := 10
    if region != "" and region == wanted_region:
        score += 8
    elif region == "":
        score += 4
    score -= 2 * extra
    if "+" in name:
        score -= 3
    return maxi(score, 0)


func _languages() -> Node:
    return get_node_or_null("/root/Languages")

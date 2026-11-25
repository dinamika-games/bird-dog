class_name ConfirmDialog
extends Control

## Ask the players a yes-or-no question before something which can not be
## undone, e.g., deleting a voyage, or tell them something with one button
## (see [method tell]).
##
## The dialog dims the screen and shows the question with two big buttons.
## While it is open, it is modal: the HandButtons behind it do not react, so
## that a hand which rests somewhere else presses nothing. Esc answers "no",
## Enter "yes". A dialog which only tells has one button, which Esc and Enter
## both press.

## The players answered "yes".
signal confirmed

## The players answered "no" (or pressed Esc).
signal cancelled

## The panel of the dialog, and where the buttons start, in pixels.
const PANEL := Rect2(260, 260, 1400, 560)
const BUTTONS_TOP := 600.0

## The largest and the smallest size of the text; a long text gets smaller
## until it fits above the buttons.
const TEXT_SIZE := 52
const MIN_TEXT_SIZE := 30

## The group of the open dialogs; the HandButtons outside of them stay quiet.
const GROUP := "modal_dialog"

var question := ""
var yes_text := ""
var no_text := ""

var _answered := false


## Create a dialog on the menu screen and show it on top, under the cursor.
static func ask(
    screen: MenuScreen, question_text: String, yes: String, no: String
) -> ConfirmDialog:
    var dialog := ConfirmDialog.new()
    dialog.question = question_text
    dialog.yes_text = yes
    dialog.no_text = no
    screen.add_child(dialog)
    screen.move_child(screen.cursor, screen.get_child_count() - 1)
    return dialog


## Tell the players something on the menu screen, with one button which closes
## the dialog (and emits [signal confirmed]).
static func tell(screen: MenuScreen, text: String, ok: String) -> ConfirmDialog:
    return ask(screen, text, ok, "")


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_to_group(GROUP)

    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 80)
    actions.alignment = BoxContainer.ALIGNMENT_CENTER
    actions.position = Vector2(0, 600)
    actions.size = Vector2(1920, 140)
    add_child(actions)

    var entries := [[yes_text, _confirm]]
    if no_text != "":
        entries.append([no_text, _cancel])
    for entry in entries:
        var button := HandButton.new()
        button.custom_minimum_size = Vector2(440, 130)
        button.text = entry[0]
        button.text_size = 44
        button.pressed.connect(entry[1])
        actions.add_child(button)

    # NOTE (mristin):
    # The question waits until the voice has said the heading of the screen
    # (a dialog may open together with the screen, e.g., a new chapter).
    Speech.say(self, question, false)


func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    if event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        if no_text == "":
            _confirm()
        else:
            _cancel()
    elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
        get_viewport().set_input_as_handled()
        _confirm()


## Ask whether to quit the game, so that Esc never quits it by accident; quit
## on "yes". On a screen without a hand cursor (e.g., the instruction), the
## dialog brings its own, so that the hands and the mouse can answer.
static func ask_to_quit(parent: Node) -> ConfirmDialog:
    var dialog := ConfirmDialog.new()
    dialog.question = parent.tr("Do you really want to quit the game?")
    dialog.yes_text = parent.tr("Yes, quit")
    dialog.no_text = parent.tr("No, stay")
    dialog.confirmed.connect(parent.get_tree().quit)
    # NOTE (mristin):
    # The own cursor enters the tree before the buttons of the dialog, so that
    # they find it, and then moves on top of them.
    var cursor: HandCursor = null
    if not parent is MenuScreen:
        cursor = HandCursor.new()
        dialog.add_child(cursor)
    parent.add_child(dialog)
    if cursor != null:
        dialog.move_child(cursor, -1)
    else:
        parent.move_child((parent as MenuScreen).cursor, -1)
    return dialog


func _confirm() -> void:
    if _answered:
        return
    _answered = true
    confirmed.emit()
    queue_free()


func _cancel() -> void:
    if _answered:
        return
    _answered = true
    cancelled.emit()
    queue_free()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
    var panel := PANEL
    draw_rect(Rect2(panel.position + Vector2(10, 12), panel.size), Color(0, 0, 0, 0.25))
    draw_rect(panel, Paper.PAPER)
    draw_rect(panel, Paper.INK, false, 4.0)
    draw_rect(panel.grow(-14), Color(Paper.INK, 0.4), false, 2.0)
    var font := ThemeDB.fallback_font
    var width := panel.size.x - 120
    var text_size := text_size_of(question)
    var height := (
        font.get_multiline_string_size(question, HORIZONTAL_ALIGNMENT_CENTER, width, text_size).y
    )
    # NOTE (mristin):
    # The text stands in the middle of the space above the buttons.
    var top := panel.position.y + (BUTTONS_TOP - panel.position.y - height) * 0.5
    draw_multiline_string(
        font,
        Vector2(panel.position.x + 60, top + font.get_ascent(text_size)),
        question,
        HORIZONTAL_ALIGNMENT_CENTER,
        width,
        text_size,
        -1,
        Paper.INK
    )


## The size of the text at which it fits above the buttons (at least
## [constant MIN_TEXT_SIZE]).
static func text_size_of(text: String) -> int:
    var font := ThemeDB.fallback_font
    var width := PANEL.size.x - 120
    var room := BUTTONS_TOP - PANEL.position.y - 40.0
    var text_size := TEXT_SIZE
    while text_size > MIN_TEXT_SIZE:
        var height := (
            font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, text_size).y
        )
        if height <= room:
            break
        text_size -= 2
    return text_size

class_name Speech
extends RefCounted

## Say texts aloud from anywhere in the game (see the autoload Voice in
## scenes/voice/voice.gd). Without the Voice (e.g., in a test which runs a
## screen alone), nothing is said.


## Say the text (already translated) aloud; [param interrupt] stops what is
## being said, otherwise the text waits its turn. [param code] says it in
## another language than the game's (e.g., on the language select).
static func say(node: Node, text: String, interrupt := true, code := "") -> void:
    var voice := _voice(node)
    if voice != null:
        voice.say(text, interrupt, code)


## Stop what is being said (e.g., when the players skip it).
static func stop(node: Node) -> void:
    var voice := _voice(node)
    if voice != null:
        voice.stop()


## Whether something is being said now.
static func is_speaking(node: Node) -> bool:
    var voice := _voice(node)
    return voice != null and voice.is_speaking()


static func _voice(node: Node) -> Node:
    if node == null or not node.is_inside_tree():
        return null
    return node.get_tree().root.get_node_or_null("Voice")

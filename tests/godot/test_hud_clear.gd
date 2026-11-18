extends SceneTree
## Check that the HUD never covers the player's boat (see HudDodge), with one
## and with two players: the panels stand clear of the middle of the view at
## home, and wherever the camera puts the boat, whichever way it heads and
## however long the ship, every panel stands clear of the boat, of the webcam
## and of the other panels, inside the view (or hides, rarely).

const MISSION := preload("res://scenes/mission/mission.tscn")

## The lengths of the ships (see data/world/ships/): the shortest, the bracera
## and the longest.
const LENGTHS: Array[float] = [0.8, 1.0, 1.35]

## The boat comes off the middle of the view by the look-ahead of the camera,
## and lags behind it a little more when fast (see SeaView.follow).
const LAG := 120.0

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


func _frames(count: int) -> void:
    for i in range(count):
        await process_frame


func _run() -> void:
    for players in [1, 2]:
        var scene: Node = MISSION.instantiate()
        scene.mission_id = "bell_of_grebastica"
        scene.next_scene = ""
        scene.record_result = false
        scene.players = players
        root.add_child(scene)
        await _frames(2)
        for view: SeaView in scene._views:
            for with_tip in [false, true]:
                var label := (
                    "%d player(s), view %d%s"
                    % [players, view.player, ", with a tip" if with_tip else ""]
                )
                _check_view(view, label, with_tip)
        scene.free()
        await _frames(1)

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)


func _check_view(view: SeaView, label: String, with_tip: bool) -> void:
    var area := Rect2(Vector2.ZERO, view.size)
    _check(view.homes.size() == 9, "%s: all the panels keep clear of the boat" % label)
    _check(not view.reserved.is_empty(), "%s: the webcam is reserved" % label)
    var zone := SeaView.rest_zone(view.size)
    for home in view.homes:
        _check(area.encloses(home), "%s: the panel at %s stands in the view" % [label, home])
        _check(
            not home.intersects(zone), "%s: the panel at %s leaves the middle free" % [label, home]
        )
        for reserved in view.reserved:
            _check(
                not home.intersects(reserved),
                "%s: the panel at %s leaves the webcam free" % [label, home]
            )

    # NOTE (mristin):
    # At rest in the middle, no panel moves.
    for i in range(16):
        var boat := _boat_at(view.size * 0.5, TAU * i / 16.0, 1.0)
        var slots := HudDodge.dodge(view.homes, view.homes, boat, area, view.reserved)
        _check(slots == view.homes, "%s: no panel moves for the boat at rest" % label)

    # NOTE (mristin):
    # Sail the boat to and fro over every place where the camera may put it,
    # so that the panels move from slot to slot as in the game.
    var reach := SeaView.LOOK_AHEAD * minf(view.size.x, view.size.y) * 0.5 + LAG
    var center := view.size * 0.5
    var errors := 0
    var moves := 0
    var hides := 0
    var samples := 0
    # NOTE (mristin):
    # The tips show now and then; between them, their panel takes no place.
    var idle: Array[bool] = []
    for i in range(view.homes.size()):
        idle.append(view._dodgers[i] == view.hint and not with_tip)
    for length in LENGTHS:
        for h in range(8):
            var heading := TAU * h / 8.0
            var slots := view.homes.duplicate()
            var step := 16.0
            var y := -reach
            var row := 0
            while y <= reach:
                var x := -reach
                while x <= reach:
                    var off := Vector2(x if row % 2 == 0 else -x, y)
                    x += step
                    if off.length() > reach:
                        continue
                    var at := center + off
                    var boat := _boat_at(at, heading, length)
                    slots = HudDodge.dodge(view.homes, slots, boat, area, view.reserved, idle)
                    samples += 1
                    for i in range(slots.size()):
                        if idle[i]:
                            continue
                        if slots[i] == HudDodge.HIDDEN:
                            hides += 1
                            continue
                        if slots[i] != view.homes[i]:
                            moves += 1
                        var wrong := ""
                        if slots[i].intersects(boat):
                            wrong = "covers the boat"
                        elif not area.encloses(slots[i]):
                            wrong = "leaves the view"
                        else:
                            for reserved in view.reserved:
                                if slots[i].intersects(reserved):
                                    wrong = "covers the webcam"
                            for j in range(i):
                                if not idle[j] and slots[i].intersects(slots[j]):
                                    wrong = "overlaps the panel at %s" % slots[j]
                        if wrong != "":
                            errors += 1
                            if errors <= 10:
                                _check(
                                    false,
                                    (
                                        "%s: the panel of %s %s at %s (boat %.2f at %s, %d°)"
                                        % [
                                            label,
                                            view.homes[i],
                                            wrong,
                                            slots[i],
                                            length,
                                            at,
                                            h * 45
                                        ]
                                    )
                                )
                y += step
                row += 1
    print(
        (
            "%s: %d places of the boat, %d moves and %d hides of the panels, %d errors"
            % [label, samples, moves, hides, errors]
        )
    )
    _check(errors == 0, "%s: the HUD never covers the boat (%d errors)" % [label, errors])
    # NOTE (mristin):
    # A panel hides only when no place is free; it should hardly ever happen.
    _check(
        hides * 100 <= samples,
        "%s: the panels hide for at most 1%% of the places of the boat (%d)" % [label, hides]
    )


func _boat_at(at: Vector2, heading: float, length: float) -> Rect2:
    var footprint := SeaBoat.footprint(heading, length)
    return Rect2(footprint.position + at, footprint.size)

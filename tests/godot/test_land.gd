extends SceneTree
## Check where the chart has the land (see ChartView.is_land): a thin line out
## at sea, north of Corfu, where a slanted ray runs through a corner of the
## mainland, is the sea, and the rest of the chart agrees with the polygons of
## the land, up to the points where Geometry2D.is_point_in_polygon counts a
## corner twice.

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var chart := ChartView.new()
    root.add_child(chart)
    await process_frame

    # NOTE (mristin):
    # The end-to-end test of two players found a boat "on the land" at the
    # first point (oranges_of_parga); Geometry2D counted the line through
    # the others as the land, too.
    for km in [
        Vector2(322.3813, 358.6647),
        Vector2(322.381591796875, 358.6650695800781),
        Vector2(322.3816223144531, 358.66510009765625),
    ]:
        _check(not chart.is_land(km), "the sea north of Corfu at %s is the land" % km)
    _check(chart.is_land(Vector2(310.0, 370.0)), "Corfu is the sea")
    _check(not chart.is_land(Vector2(0.0, 55.6)), "the middle of the Adriatic is the land")
    var bounds := World.bounds_km()
    _check(chart.is_land(bounds.position - Vector2.ONE), "beyond the chart is the sea")

    # NOTE (mristin):
    # Where is_land and Geometry2D disagree, Geometry2D must be wrong: the
    # points around agree with is_land.
    var disagree := 0
    var step := 2.5
    var y := bounds.position.y + step / 2.0
    while y < bounds.end.y:
        var x := bounds.position.x + step / 2.0
        while x < bounds.end.x:
            var km := Vector2(x, y)
            var land := chart.is_land(km)
            if land != _godot_land(chart, km):
                disagree += 1
                var around := 0
                for offset in [
                    Vector2(0.01, 0), Vector2(-0.01, 0), Vector2(0, 0.01), Vector2(0, -0.01)
                ]:
                    if _godot_land(chart, km + offset) == land:
                        around += 1
                _check(around >= 3, "is_land at %s is %s, but not around it" % [km, land])
            x += step
        y += step
    print("Checked the land on a grid of %.1f km: %d points disagree" % [step, disagree])

    for failure in _failures:
        print("FAIL ", failure)
    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)


static func _godot_land(chart: ChartView, km: Vector2) -> bool:
    for i in range(chart._land.size()):
        if chart._boxes[i].has_point(km) and Geometry2D.is_point_in_polygon(km, chart._land[i]):
            return true
    return false

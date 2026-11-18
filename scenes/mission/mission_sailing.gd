class_name MissionSailing
extends RefCounted

## The sailing of the mission screen (see MissionScreen), frame by frame: the
## steering, the wind, the hazards and the clock, the boats together, towed or
## entering a port, the rival and the race, the damage of the hull, and the
## keys (C for the chart, Esc to leave the mission).

var m: MissionScreen


func _init(mission: MissionScreen) -> void:
    m = mission


func unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_C or (event.keycode == KEY_ESCAPE and m._full_chart != null):
        m.get_viewport().set_input_as_handled()
        _toggle_chart()
    elif event.keycode == KEY_ESCAPE and m._leave_dialog == null:
        m.get_viewport().set_input_as_handled()
        ask_to_leave()


## C shows the chart of the whole Adriatic, so that the crew gets its
## bearings (see FullChart); the game waits meanwhile.
func _toggle_chart() -> void:
    if m._full_chart != null:
        m._all_paused = m._full_chart.close()
        m._full_chart = null
    elif m._leave_dialog == null:
        m._full_chart = FullChart.open(m._overlay, m._views[0].minimap, m._all_paused)
        m._all_paused = true


## Esc asks first, so that a child does not leave the mission by accident; the
## game waits meanwhile.
func ask_to_leave() -> void:
    m._paused_before = m._all_paused
    m._all_paused = true
    m._leave_dialog = ConfirmDialog.new()
    m._leave_dialog.question = m.tr("Leave the mission? It is saved, and you can continue later.")
    m._leave_dialog.yes_text = m.tr("Yes, leave")
    m._leave_dialog.no_text = m.tr("No, sail on")
    m._leave_dialog.confirmed.connect(leave_now)
    m._leave_dialog.cancelled.connect(_stay)
    m._overlay.add_child(m._leave_dialog)
    m._overlay.move_child(m._shared_cursor, -1)
    m._shared_cursor.visible = true


func _stay() -> void:
    m._leave_dialog = null
    m._all_paused = m._paused_before
    m._shared_cursor.visible = m._shared_card.visible or m._exchange != null


func leave_now() -> void:
    m._save_progress()
    if m.next_scene == "":
        m.get_tree().quit()
    else:
        m.get_tree().change_scene_to_file(m.next_scene)


func process(delta: float) -> void:
    var poses: Array = m._pose.GetPlayers()
    for helm in m._helms:
        helm.steer = 0.0 if helm.towed else m._steer_of(helm.player, poses)
        m._wheel.steers[helm.player] = helm.steer
    # NOTE (mristin):
    # The webcam steps aside while nobody sails (a scene fills the screen).
    m._wheel.visible = not m._all_paused and m._busy.has(false)
    if m._all_paused:
        return

    var sailing: Array[Helm] = []
    var towed: Array[Helm] = []
    for helm in m._helms:
        if m._busy[helm.player]:
            continue
        if helm.towed:
            towed.append(helm)
        else:
            sailing.append(helm)
    if sailing.is_empty() and towed.is_empty():
        return

    var run := m._run
    m._wind.update(delta)
    if not sailing.is_empty():
        m._hazards.update(delta, sailing, m._chart.targets)
    var together := (
        m.players > 1 and m._helms[0].km.distance_to(m._helms[1].km) < MissionScreen.TOGETHER_KM
    )
    var boost := MissionScreen.TOGETHER_BOOST if together else 1.0
    if run.bag.has_effect("speed"):
        boost *= MissionScreen.NEW_SAILS
    m._wind.warning_seconds = (
        SeaWind.FISHERMAN_SECONDS if run.bag.has_effect("weather") else SeaWind.WARNING_SECONDS
    )

    for helm in m._helms:
        helm.fit(run.hold(helm.player).ship, run.bag)

    var sailed := 0.0
    var tow_km := 0.0
    for helm in towed:
        tow_km = maxf(tow_km, m._story.tow_step(helm, delta))
    for helm in sailing:
        var factor := m._hazards.speed_factor(helm.km)
        m._views[helm.player].shade.amount = 1.0 if factor < 1.0 else 0.0
        helm.heading += m._hazards.gust(helm.km, delta)
        sailed = maxf(
            sailed, helm.sail(delta, m._wind, m._chart, m._mission.sea.speed_scale, boost * factor)
        )
        _check_damage(helm, delta)

    # NOTE (mristin):
    # The clock runs while a boat is at sea, as fast as the boat which sails
    # the farthest; a towed boat is slower, and its days run slower, too.
    run.pass_days(maxf(sailed, tow_km * MissionScreen.TOW_SLOWER) / MissionScreen.KM_PER_DAY)
    for helm in sailing:
        m._tips.check(helm, delta, run, m._chart, m._hazards, m._wind)
    var marks := m._hazards.marks()
    _update_rival(delta, marks)
    _update_race(delta, sailing, marks)
    for view in m._views:
        view.minimap.marks = marks
    m._rope.visible = together
    if together:
        m._rope.points = PackedVector2Array([m._helms[0].boat.position, m._helms[1].boat.position])
    place_boats(false, delta)

    for helm in sailing:
        if m._busy[helm.player] or helm.towed:
            continue
        var hold := run.hold(helm.player)
        if hold.is_out_of_provisions():
            m._story.tow(
                helm.player,
                MissionRun.line("Out of food and water! Fishermen tow you to {port}."),
                MissionRun.line("Out of food and water! A fishing boat towed you to {port}.")
            )
        elif hold.is_wrecked():
            m._story.tow(
                helm.player,
                MissionRun.line("The hull is broken! Fishermen tow you to {port}."),
                MissionRun.line("The hull is broken! A fishing boat towed you to {port}.")
            )
        else:
            _warn_low(helm.player)
            _check_ports(helm)
    if towed.is_empty():
        m._check_meeting()


## Tell the crew once per leg when the food runs low (the panel blinks, too).
func _warn_low(player: int) -> void:
    if m._warned_low[player] or m._run.provisions_share(player) >= ProvisionsPanel.LOW:
        return
    m._warned_low[player] = true
    m._say(m.tr("Running low! Stop in a port!"), player)


## The rival of a trail (e.g., the recruiter of mission 2) sails, shows on the
## minimap, and may make the trail longer.
func _update_rival(delta: float, marks: Array[Dictionary]) -> void:
    var trail := m._run.step() as TrailStep
    if trail == null or not trail.rival:
        return
    var speed := Helm.BASE_KM_PER_SECOND * m._mission.sea.speed_scale
    var first := Rival.update(m._run, trail, delta, speed)
    if first != null:
        m._say(Grammar.format(m.tr(trail.rival_line), {"port": first.name}), -1)
        m._story.update_targets()
    var at: Variant = Rival.position(m._run, trail)
    if at != null:
        marks.append({"km": at, "kind": "rival", "radius": 0.0})


## The race of a RaceStep goes on: the boats round the buoys, the rival sails
## the course, shows on the chart and the minimap, and may be back first.
func _update_race(delta: float, sailing: Array[Helm], marks: Array[Dictionary]) -> void:
    var race := m._run.step() as RaceStep
    if race == null or not race.is_racing(m._run):
        m._race.visible = false
        return
    var boats: Array[Vector2] = []
    for helm in sailing:
        boats.append(helm.km)
    var events := race.update(m._run, boats, delta, m._mission.sea.speed_scale, m._wind)
    if events["rounded"] > 0:
        var text := m.tr("Buoy {number} rounded!")
        m._say(Grammar.format(text, {"number": events["rounded"]}), -1)
        m._sfx.play("coins")
        m._story.update_targets()
    if events["cut"]:
        m._say(m.tr(race.cut_line), -1)
    if events["lost"]:
        m._say(m.tr(race.lost_line), -1)
        m._story.update_targets()
    m._race.marker_scale = m._chart.marker_scale
    m._race.show_race(race, m._run)
    var at := race.rival_at(m._run)
    if not at.is_empty():
        marks.append({"km": at["km"], "kind": "rival", "radius": 0.0})


## The reefs and the cliffs damage the hull (see DESIGN.md, "Reefs and
## cliffs"); the rest of the coast never does.
func _check_damage(helm: Helm, delta: float) -> void:
    helm.bump_cooldown = maxf(0.0, helm.bump_cooldown - delta)
    if helm.bump_cooldown > 0.0 or m._run.bag.has_effect("pilot"):
        return
    var hold := m._run.hold(helm.player)
    if m._chart.is_reef(helm.km):
        var share := clampf(helm.speed / Helm.BASE_KM_PER_SECOND, 0.4, 1.0)
        hold.add_damage(MissionScreen.REEF_DAMAGE * share)
        helm.speed *= 0.3
        helm.bump_cooldown = 2.5
        m._say(m.tr("Crash! A reef! The hull is damaged."), helm.player)
        m._sfx.play("crash")
    elif helm.hit_land != Vector2.INF and m._chart.is_cliff(helm.hit_land):
        hold.add_damage(MissionScreen.CLIFF_DAMAGE)
        helm.bump_cooldown = 2.0
        m._say(m.tr("Crash! The cliffs! The hull is damaged."), helm.player)
        m._sfx.play("crash")


func place_boats(snap: bool, delta := 0.0) -> void:
    var boats: Array[Dictionary] = []
    for helm in m._helms:
        helm.place(m._wind)
        boats.append(
            {"km": helm.km, "heading": helm.heading, "color": MissionScreen.COLORS[helm.player]}
        )
    for view in m._views:
        view.minimap.boats = boats
        view.rose.heading = m._helms[view.player].heading
        view.follow(m._helms[view.player], m._chart, snap, delta)
    for helm in m._helms:
        if m._tows[helm.player] != null:
            m._tows[helm.player].place(helm)
    # NOTE (mristin):
    # The shared chart keeps its size in the view which zoomed in the most.
    m._chart.marker_scale = 1.0 / m._views.map(func(view): return view.zoom).max()


func _check_ports(helm: Helm) -> void:
    var left: Port = m._left[helm.player]
    if left != null and helm.km.distance_to(World.port_km(left)) > MissionScreen.LEAVE_KM:
        m._left[helm.player] = null
    # NOTE (mristin):
    # During a race, the boats sail past the other harbours (a race port may
    # have a neighbour close by, as Trani is to Barletta).
    var race := m._run.step() as RaceStep
    var racing := race != null and race.is_racing(m._run)
    for port in World.ports():
        if port == m._left[helm.player] or (racing and port != race.port):
            continue
        if helm.km.distance_to(World.port_km(port)) < MissionScreen.ENTER_KM:
            m._story.arrive(helm.player, port)
            return

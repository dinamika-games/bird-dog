class_name MissionStory
extends RefCounted

## The story of the mission screen (see MissionScreen): the scenes of the steps
## on the cards (the briefing for the whole crew, the ports in the half of the
## player who entered), the merchant's stall and the errands of the ports, a
## boat entering a port or being towed there, and the end of the mission.

var m: MissionScreen


func _init(mission: MissionScreen) -> void:
    m = mission


## Show a scene to the whole crew, on the whole screen (the briefing).
func show_shared(scene: Dictionary, port: Port) -> void:
    m._all_paused = true
    m._shared_card.present(scene, m._run, port)
    m._shared_cursor.visible = true
    for view in m._views:
        view.show_hud(false)


func on_shared_action(action: String) -> void:
    m._run.active = 0
    var step := m._run.step()
    var next: Variant = step.act(m._run, action) if step != null and action != "leave" else null
    if next != null:
        m._shared_card.present(next, m._run, m._mission.start_port)
        return
    m._run.advance()
    m._shared_card.visible = false
    m._shared_cursor.visible = false
    if m._run.is_done():
        return
    resume_all()
    for i in range(m.players):
        _show_start(i)


## After the briefing, every crew is still in the start port: the merchant and
## the errands are there before it sets sail; then the story goes on.
func _show_start(player: int) -> void:
    var port := m._mission.start_port
    m._in_port[player] = port
    m._stalls[player] = Merchant.draw_stall(port, m._session.owned, m._run.rng)
    var local: Person = port.locals[0] if not port.locals.is_empty() else null
    var said: Array = [
        MissionRun.line("Fair winds, captain! Do you need anything before you set sail?")
    ]
    var scene := MissionStep.talk(local, said, MissionRun.line("Set sail!"))
    PortScene.add_buttons(scene, port, m._run)
    m._port_scenes[player] = scene
    show(player, scene, port)


func resume_all() -> void:
    m._all_paused = false
    for i in range(m.players):
        m._views[i].show_hud(not m._busy[i])
    update_targets()


## Show a scene in the half of the player.
func show(player: int, scene: Dictionary, port: Port) -> void:
    m._busy[player] = true
    m._scene_steps[player] = m._run.step()
    m._helms[player].speed = 0.0
    m._cards[player].present(scene, m._run, port)
    m._cards[player].get_meta("cursor").visible = true
    m._views[player].show_hud(false)
    update_targets()  # A scene may change them (e.g., the goods collected).


func _show_opening(player: int) -> void:
    m._run.active = player
    var step := m._run.step()
    if step == null:
        return
    var opening: Variant = step.opening(m._run)

    # NOTE (mristin):
    # A step may continue right where the crew is (e.g., the line-up found
    # the doctor in Dubrovnik, and the medicine is in Dubrovnik, too).
    var port: Port = m._in_port[player]
    if opening == null and port != null:
        opening = step.arrive(m._run, port)
    if opening != null:
        if step is CelebrationStep and step.sound != "":
            m._sfx.play(step.sound)
        show(player, opening, port)
    else:
        resume(player)


func resume(player: int) -> void:
    m._busy[player] = false
    m._in_port[player] = null
    m._cards[player].visible = false
    m._cards[player].get_meta("cursor").visible = false
    m._views[player].show_hud(not m._all_paused)
    update_targets()


func update_targets() -> void:
    var step := m._run.step()
    var targets: Array[Port] = []
    if step != null:
        targets = step.target_ports(m._run)
    m._chart.targets = targets
    m._chart.errand_ports = Errands.ports(m._run)
    for view in m._views:
        view.minimap.targets = targets
        view.minimap.errand_ports = m._chart.errand_ports
        view.arrow.targets = targets


func on_action(action: String, player: int) -> void:
    m._run.active = player
    if _on_shop(action, player):
        return
    var step := m._run.step()

    # NOTE (mristin):
    # With two players, the other crew may have moved the story on while this
    # scene was open; its answers then only close it.
    if step != m._scene_steps[player]:
        resume(player)
        return
    var next: Variant = null
    if step != null and action != "leave":
        next = step.act(m._run, action)
    if next != null:
        show(player, next, m._in_port[player])
        return
    m._run.advance()
    if m._run.is_done():
        return
    # NOTE (mristin):
    # The targets change in the port (a task done, the target fled), so that
    # the chart (C) shows them already there, not only at sea.
    update_targets()
    _show_opening(player)


## The actions of the merchant's stall; return whether it was one of them.
func _on_shop(action: String, player: int) -> bool:
    var port: Port = m._in_port[player]
    if action == "shop":
        show(player, _shop_scene(player, MissionRun.line("What would you like, captain?")), port)
        return true
    if action.begins_with("buy:"):
        var booster: Booster = m._stalls[player][int(action.get_slice(":", 1))]
        var bought := false
        if booster.decoration != null and player < m._crew.captains.size():
            var captain: Dictionary = m._crew.captains[player]
            bought = Merchant.buy_decoration(booster, m._run, m._session, captain)
            m._helms[player].boat.decorations = World.boat_decorations(captain)
        elif booster.decoration == null:
            bought = m._run.bag.buy(booster)
        if bought:
            m._sfx.play("coins")
        var thanks := MissionRun.line(
            "A fine choice, captain! {booster} is yours.", {"booster": booster.name}
        )
        show(player, _shop_scene(player, thanks), port)
        return true
    if action == "close_shop":
        show(player, m._port_scenes[player], port)
        return true
    return _on_errand(action, player)


## The actions of the errands of the port; return whether it was one of them.
func _on_errand(action: String, player: int) -> bool:
    var port: Port = m._in_port[player]
    if action == "errand":
        var offer := Errands.offer(port, m._run.rng)
        m._offers[player] = offer
        show(player, Errands.ask_scene(offer, m._port_scenes[player].get("person")), port)
        return true
    if action == "errand_yes":
        var offer: Dictionary = m._offers[player]
        m._run.hold(player).cargo.append(offer["item"])
        m._run.errands.append(offer)
        if m._tips.wants("errand"):
            m._tips.show_tip(player, "errand")
        var buttons: Array = m._port_scenes[player]["buttons"]
        m._port_scenes[player]["buttons"] = buttons.filter(
            func(entry: Dictionary) -> bool: return entry["action"] != "errand"
        )
        update_targets()
        show(player, m._port_scenes[player], port)
        return true
    if action == "bay":
        var bay := World.port(port.bay_port_id)
        m._helms[player].heading = (World.port_km(bay) - World.port_km(port)).angle() + PI / 2
        arrive(player, bay)
        return true
    return false


## The merchant's stall in the port of the player (see Merchant).
func _shop_scene(player: int, said: Dictionary) -> Dictionary:
    var person: Person = m._port_scenes[player].get("person")
    m._run.active = player
    m._stalls[player] = m._stalls[player].filter(
        func(booster: Booster) -> bool: return Merchant.offers(booster, m._run)
    )
    return Merchant.scene(person, said, m._stalls[player], m._run, m._session)


## The boat of the player enters the port; [param first] are the lines to say
## before the scene of the port (e.g., that the boat was towed there).
func arrive(player: int, port: Port, first: Array = []) -> void:
    var run := m._run
    m._entry_headings[player] = m._helms[player].heading
    run.active = player
    m._in_port[player] = port
    m._left[player] = port
    m._warned_low[player] = false
    m._stalls[player] = Merchant.draw_stall(port, m._session.owned, run.rng)
    run.pass_days(MissionRun.PORT_DAYS)
    var hold := run.hold(player)
    var hungry := run.provisions_share(player) < ProvisionsPanel.LOW
    hold.add_ration(run.ration_days())
    run.bag.end_leg()
    var damaged := hold.damage > 0.0
    run.pass_days(hold.repair())
    var paid := Errands.deliver(run, port)
    var ducats_before := hold.ducats
    for view in m._views:
        view.minimap.visited[port.id] = true
    MissionBuilder.launch(m, port, player)

    var scene := PortScene.of(run, port, m.players)
    if scene["kind"] == "talk":
        var gained := hold.ducats - ducats_before
        if gained > 0 or not paid.is_empty():
            m._sfx.play("coins")
        scene["lines"] = PortScene.lines(
            scene, first, paid, gained, hungry, damaged, m._tips.wants("port")
        )
        PortScene.add_buttons(scene, port, run)
        m._port_scenes[player] = scene
    else:
        # NOTE (mristin):
        # A line-up has no room for the thanks, so they show as messages.
        for thanks in paid:
            m._say(run.say(thanks, player), player)
        if not paid.is_empty():
            m._sfx.play("coins")
    update_targets()
    show(player, scene, port)
    m._save_progress()


## Out of food and water, or with a broken hull: a fishing boat comes and
## tows the boat to the nearest port, slowly, around the islands, while the
## crew watches (see Tow); it costs time (see DESIGN.md, "Provisions").
## [param started] is told at once, [param reason] in the port.
func tow(player: int, started: Dictionary, reason: Dictionary) -> void:
    var helm: Helm = m._helms[player]
    var avoid := Tow.avoid(m._chart, m._hazards)
    var found := Tow.nearest_by_sea(helm.km, MissionScreen.ENTER_KM - 0.5, avoid)
    var nearest: Port = found["port"]
    var path: PackedVector2Array = found["path"]
    reason["args"] = {"port": nearest.name}
    started["args"] = {"port": nearest.name}
    m._run.pass_days(MissionScreen.TOW_DAYS)
    if path.size() < 2:
        # NOTE (mristin):
        # No way at sea (it should not happen): the boat is in the port at once.
        var km := World.port_km(nearest).distance_to(helm.km)
        m._run.pass_days(km * MissionScreen.TOW_SLOWER / MissionScreen.KM_PER_DAY)
        arrive(player, nearest, [reason])
        return
    helm.towed = true
    helm.speed = 0.0
    helm.steer = 0.0
    m._tows[player] = Tow.new(path, nearest, reason, m._chart.get_parent())
    m._say(m._run.say(started, player), player)


## The fishermen pull the boat a bit; at the end of the way, it enters the
## port. Return how far it went, in kilometres.
func tow_step(helm: Helm, delta: float) -> float:
    var a_tow: Tow = m._tows[helm.player]
    a_tow.look_out(delta, m._chart, m._hazards, MissionScreen.ENTER_KM - 0.5)
    var speed := Helm.BASE_KM_PER_SECOND * m._mission.sea.speed_scale * MissionScreen.TOW_SHARE
    var moved := a_tow.pull(helm, delta, speed)
    if a_tow.is_done():
        m._tows[helm.player] = null
        helm.towed = false
        a_tow.finish()
        arrive(helm.player, a_tow.port, [a_tow.reason])
    return moved


func on_rewarded(ducats: int) -> void:
    m._sfx.play("coins")
    var text := m.tr("+{ducats} {ducats|ducat|ducats} for the task done!")
    m._say(Grammar.format(text, {"ducats": ducats}), m._run.active)


func on_finished(stars: int) -> void:
    m._stars = stars
    # The yataks give what they collected, once (see Session.yatak_gift).
    var gift: int = m._session.yatak_gift(m._mission.id) if m.record_result else 0
    m._run.holds[0].ducats += gift
    m._all_paused = true
    for i in range(m.players):
        m._cards[i].visible = false
        m._cards[i].get_meta("cursor").visible = false
    var complete := MissionComplete.new()
    complete.mission = m._mission
    complete.run = m._run
    complete.stars = stars
    complete.ducats = m._run.ducats_total() - m._run.brought - gift
    complete.gift = gift
    complete.finished.connect(leave)
    m._overlay.add_child(complete)
    m._overlay.move_child(m._shared_cursor, -1)
    m._shared_cursor.visible = true


func leave() -> void:
    if m.record_result:
        m._session.complete(m._mission.id, m._stars, m._run.ducats_total())
    if m.next_scene == "":
        m.get_tree().reload_current_scene()
    else:
        m.get_tree().change_scene_to_file(m.next_scene)

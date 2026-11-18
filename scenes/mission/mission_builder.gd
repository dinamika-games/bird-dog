class_name MissionBuilder
extends RefCounted

## Build the mission screen (see MissionScreen): the world with the chart, the
## boats and the hazards, the view of every player with the card of its port
## scenes, and the HUD and the overlay which the players share.


static func build(m: MissionScreen) -> void:
    var world := _build_world(m)
    _build_views(m, world)
    m._tips = Tips.new(m._session, m._views)
    _build_shared(m)


static func _build_world(m: MissionScreen) -> Node2D:
    var world := Node2D.new()
    m._chart = ChartView.new()
    world.add_child(m._chart)
    m._race = RaceCourse.new()
    m._race.visible = false
    world.add_child(m._race)

    m._rope = Line2D.new()
    m._rope.width = 5.0
    m._rope.default_color = Color(Paper.GOLD, 0.8)
    m._rope.z_index = 4
    m._rope.visible = false
    world.add_child(m._rope)

    for i in range(m.players):
        var boat := SeaBoat.new()
        boat.z_index = 5
        boat.scale = Vector2.ONE * SeaView.BOAT_SCALE
        boat.color = MissionScreen.COLORS[i]
        boat.mark = str(i + 1) if m.players > 1 else ""
        boat.dolphins = true
        boat.ship = m._run.hold(i).ship
        if i < m._crew.captains.size():
            boat.decorations = World.boat_decorations(m._crew.captains[i])
            boat.initial = str(m._crew.captains[i].get("name", "")).left(1).to_upper()
        world.add_child(boat)
        m._helms.append(Helm.new(i, boat))

    m._sfx = Sfx.new()
    m.add_child(m._sfx)
    m._hazards = SeaHazards.new()
    m._hazards.setup(m._mission.sea, m._chart, m._wind, m._run, randi())
    m._hazards.said.connect(m._say)
    m._hazards.sounded.connect(m._sfx.play)
    world.add_child(m._hazards)
    return world


static func _build_views(m: MissionScreen, world: Node2D) -> void:
    for i in range(m.players):
        var view := SeaView.new()
        m.add_child(view)
        view.setup(i, m.players > 1, m._run, m._wind, world, null if i == 0 else m._views[0])
        m._views.append(view)

        # NOTE (mristin):
        # The scenes of the ports open in the half of the player who entered,
        # with a cursor which follows only that player's hands.
        var layer := CanvasLayer.new()
        layer.layer = 2
        view.viewport.add_child(layer)
        var card := StoryCard.new()
        card.compact = m.players > 1
        card.player = i if m.players > 1 else -1
        card.mirrored = i == 1
        card.size = Vector2(view.size)
        card.visible = false
        card.action_chosen.connect(m._story.on_action.bind(i))
        layer.add_child(card)
        m._cards.append(card)
        var cursor := HandCursor.new()
        if m.players > 1:
            cursor.region = Rect2(i * 0.5, 0, 0.5, 1)
        cursor.visible = false
        layer.add_child(cursor)
        card.set_meta("cursor", cursor)


static func _build_shared(m: MissionScreen) -> void:
    var hud := CanvasLayer.new()
    hud.layer = 1
    m.add_child(hud)
    if m.players > 1:
        var divider := ColorRect.new()
        divider.color = Paper.INK
        divider.position = Vector2(957, 0)
        divider.size = Vector2(6, 1080)
        divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hud.add_child(divider)

    m._wheel = WheelPanel.new()
    var steers: Array[float] = []
    var colors: Array[Color] = []
    for i in range(m.players):
        steers.append(0.0)
        colors.append(MissionScreen.COLORS[i] if m.players > 1 else Paper.INK)
    m._wheel.steers = steers
    m._wheel.colors = colors
    var looks: Array[Dictionary] = []
    for i in range(mini(m.players, m._crew.captains.size())):
        looks.append(m._crew.captains[i])
    m._wheel.looks = looks
    var wheel_rect := Rect2(760, 780, 400, 284) if m.players > 1 else Rect2(24, 690, 480, 340)
    m._wheel.position = wheel_rect.position
    m._wheel.size = wheel_rect.size
    hud.add_child(m._wheel)
    for view in m._views:
        view.reserve(Rect2(m._wheel.position - view.position, m._wheel.size))

    m._overlay = CanvasLayer.new()
    m._overlay.layer = 3
    m.add_child(m._overlay)
    m._shared_card = StoryCard.new()
    m._shared_card.visible = false
    m._shared_card.action_chosen.connect(m._story.on_shared_action)
    m._overlay.add_child(m._shared_card)
    m._shared_cursor = HandCursor.new()
    m._shared_cursor.visible = false
    m._overlay.add_child(m._shared_cursor)


## Put a boat (or, with -1, all of them) into the sea near the port, heading
## away from it.
static func launch(m: MissionScreen, port: Port, player: int) -> void:
    var center := World.port_km(port)
    var near := center
    for helm in m._helms:
        if player >= 0 and helm.player != player:
            continue
        var kept: Variant = ChartView.leaving_heading(port, m._entry_headings.get(helm.player))
        var departure := m._chart.departure(near, center, kept)
        helm.km = departure["km"]
        helm.heading = departure["heading"]
        helm.speed = 0.0
        near = helm.km

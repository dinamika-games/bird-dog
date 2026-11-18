class_name SeaView
extends SubViewportContainer

## What one player sees at sea (see DESIGN.md, "Two players"): a SubViewport
## on the shared chart with a camera which follows the player's boat, and the
## player's own HUD: the clue, the days, the hull of their boat with its cargo
## and passengers, the rations of food and water (a column of tokens), the boosters, the wind, the
## minimap, the arrow to the target, the toasts and the shade of the storm
## clouds.
##
## With one player, the view fills the screen; with two, every player has a
## half of it (960 x 1080), as in ergo-chaos, and the panels stand mirrored so
## that the webcam fits between the two halves at the bottom.
##
## The HUD never covers the player's boat: the middle of the view, where the
## camera keeps it, stays clear of the panels, and when the camera looks ahead
## and the boat comes under a panel, the panel moves away (see HudDodge).

## The boats are this large on the chart at the zoom of 1; they keep this
## (small) size on the screen whatever the zoom of the camera (see ChartZoom),
## so that they fit into the channels.
const BOAT_SCALE := 1.0

## The camera measures how far to zoom in this often, in seconds.
const ZOOM_MEASURE_SECONDS := 0.2

## The camera eases in to a larger zoom over about this long, in seconds...
const ZOOM_IN_SECONDS := 1.0

## ...and out again more slowly, so that it does not pump among the islands.
const ZOOM_OUT_SECONDS := 2.0

## When zoomed in fully, the camera looks ahead of the boat by this share of
## the half of the view, so that the crew sees the channel ahead.
const LOOK_AHEAD := 0.35

## The places of the panels of the HUD (see [method layout]) for the left half
## (two players) and for the whole screen (one player): their positions and
## their sizes before [constant HALF_SCALE]. The middle of the view, where the
## camera keeps the boat, stays clear of them (see [method rest_zone]).
const HALF_LAYOUT := {
    "banner": Rect2(12, 8, 920, 130),
    "days": Rect2(12, 116, 332, 110),
    "hull": Rect2(12, 207, 332, 90),
    "bar": Rect2(12, 283, 300, 80),
    "provisions": Rect2(12, 351, 96, 276),
    "rose": Rect2(711, 116, 316, 360),
    "cargo": Rect2(711, 394, 316, 144),
    "minimap": Rect2(12, 840, 290, 296),
    "hint": Rect2(240, 870, 410, 260),
}
const FULL_LAYOUT := {
    "days": Rect2(30, 24, 420, 120),
    "hull": Rect2(30, 160, 420, 90),
    "bar": Rect2(30, 264, 420, 90),
    "cargo": Rect2(30, 364, 420, 144),
    "provisions": Rect2(464, 190, 104, 318),
    "banner": Rect2(490, 24, 1000, 150),
    "rose": Rect2(1560, 0, 340, 360),
    "minimap": Rect2(1500, 640, 390, 410),
    "hint": Rect2(560, 860, 800, 190),
}

## In a half of the screen, the panels draw this much smaller, so that a panel
## which the boat comes under finds a free place elsewhere (see HudDodge).
const HALF_SCALE := 0.75

## The player (0 or 1) whose boat the view follows.
var player := 0

## Whether the view is a half of the screen (two players).
var half := false

## How far the camera zooms in now (see ChartZoom), and where it goes.
var zoom := 1.0
var target_zoom := 1.0

var viewport: SubViewport
var camera: Camera2D
var minimap: Minimap
var arrow: TargetArrow
var toast: Toast
var shade: CloudShade
var hint: HintPanel
var rose: WindRose

## The places of the panels which keep clear of the boat (see HudDodge): their
## homes in the layout, the slots they move to, and the places of the view no
## panel goes to (the webcam).
var homes: Array[Rect2] = []
var slots: Array[Rect2] = []
var reserved: Array[Rect2] = []

var _hud: CanvasLayer
var _dodgers: Array[Control] = []
var _zoom_timer := 0.0


## Build the view; [param world] is the world to show: the first view holds
## the world, the second shares its World2D.
func setup(
    the_player: int, is_half: bool, run: MissionRun, wind: SeaWind, world: Node2D, shared: SeaView
) -> void:
    player = the_player
    half = is_half
    var width := 960 if half else 1920
    position = Vector2(player * 960 if half else 0, 0)
    size = Vector2(width, 1080)
    # NOTE (mristin):
    # A SubViewportContainer forwards the mouse to its viewport only if it does
    # not ignore the mouse; the cards of the ports and their cursors live in the
    # viewport, and the mouse clicks there for testing.
    mouse_filter = Control.MOUSE_FILTER_PASS

    viewport = SubViewport.new()
    viewport.size = Vector2i(width, 1080)
    viewport.handle_input_locally = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    if shared == null:
        viewport.add_child(world)
    else:
        viewport.world_2d = shared.viewport.world_2d

    camera = Camera2D.new()
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 4.0
    viewport.add_child(camera)
    camera.make_current()

    _hud = CanvasLayer.new()
    viewport.add_child(_hud)
    _build_hud(run, wind, width)


## The places of the panels of the HUD in the view of [param the_player], as
## large as they draw: the positions of the right half are mirrored, so that the
## webcam fits between the two halves at the bottom.
static func layout(is_half: bool, the_player: int) -> Dictionary:
    var result := {}
    var source: Dictionary = HALF_LAYOUT if is_half else FULL_LAYOUT
    for name: String in source:
        var rect: Rect2 = source[name]
        rect.size *= scale_of(is_half)
        if is_half and the_player == 1:
            rect.position.x = 960 - rect.position.x - rect.size.x
        result[name] = rect
    return result


## How large the panels of the HUD draw (see [constant HALF_SCALE]).
static func scale_of(is_half: bool) -> float:
    return HALF_SCALE if is_half else 1.0


## Where the boat of the standard length (see Ship) stands in a view of
## [param view_size] when the camera does not look ahead, whichever way it
## heads, with the margin at which the panels leave (see HudDodge). The panels
## stand clear of it at home, so that they move only when the boat sails off
## the middle.
static func rest_zone(view_size: Vector2) -> Rect2:
    var rect := Rect2(view_size * 0.5, Vector2.ZERO)
    for i in range(36):
        var footprint := SeaBoat.footprint(TAU * i / 36.0)
        rect = rect.merge(Rect2(footprint.position + view_size * 0.5, footprint.size))
    return rect.grow(HudDodge.LEAVE_MARGIN)


## Place a panel at [param rect] (see [method layout]), drawn at the scale of
## the view; a panel which [param dodges] keeps clear of the boat (see
## HudDodge).
func _place(control: Control, rect: Rect2, dodges := true) -> void:
    var scale_factor := scale_of(half) if dodges else 1.0
    control.position = rect.position
    control.scale = Vector2.ONE * scale_factor
    control.size = rect.size / scale_factor
    _hud.add_child(control)
    if dodges:
        _dodgers.append(control)
        homes.append(rect)
        slots.append(rect)


## Keep the panels of the HUD off the place [param reserved] of the view (in
## its coordinates), e.g., the webcam which stands over the views.
func reserve(reserved_rect: Rect2) -> void:
    var clipped := reserved_rect.intersection(Rect2(Vector2.ZERO, size))
    if clipped.has_area():
        reserved.append(clipped)
        for home in homes:
            assert(not home.intersects(clipped), "A panel of the HUD stands under %s" % clipped)


func _build_hud(run: MissionRun, wind: SeaWind, width: int) -> void:
    shade = CloudShade.new()
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _place(shade, Rect2(0, 0, width, 1080), false)

    var banner := ClueBanner.new()
    banner.run = run
    var days := DaysPanel.new()
    days.run = run
    var provisions := ProvisionsPanel.new()
    provisions.run = run
    provisions.player = player
    var hull := HullPanel.new()
    hull.run = run
    hull.player = player
    var bar := BoosterBar.new()
    bar.run = run
    rose = WindRose.new()
    rose.wind = wind
    var cargo := CargoPanel.new()
    cargo.run = run
    cargo.player = player
    minimap = Minimap.new()
    hint = HintPanel.new()
    hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var places := layout(half, player)
    var zone := rest_zone(Vector2(width, 1080))
    var panels := {
        "banner": banner,
        "days": days,
        "hull": hull,
        "bar": bar,
        "provisions": provisions,
        "rose": rose,
        "cargo": cargo,
        "minimap": minimap,
        "hint": hint,
    }
    for name: String in panels:
        assert(
            not places[name].intersects(zone),
            "The panel %s of the HUD stands where the boat rests" % name
        )
        _place(panels[name], places[name])

    # NOTE (mristin):
    # The arrow and the toasts draw over the panels; they point at the sea and
    # stay clear of the middle, so they do not dodge. The tips draw over all.
    arrow = TargetArrow.new()
    arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _place(arrow, Rect2(0, 0, width, 1080), false)
    toast = Toast.new()
    toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _place(toast, Rect2(0, 0, width, 1080), false)
    _hud.move_child(hint, -1)


## Show or hide the HUD (it hides while a scene of a port is open).
func show_hud(shown: bool) -> void:
    _hud.visible = shown


## Follow the boat of the helm with the camera, zooming in among the islands
## (see ChartZoom) and looking ahead of the boat when zoomed in. The boat keeps
## its size on the screen.
func follow(helm: Helm, chart: ChartView, snap := false, delta := 0.0) -> void:
    _zoom_timer -= delta
    if snap or _zoom_timer <= 0.0:
        _zoom_timer = ZOOM_MEASURE_SECONDS
        target_zoom = chart.zoom_map.zoom(helm.km)
    var boat := helm.boat
    if snap:
        zoom = target_zoom
    else:
        var seconds := ZOOM_IN_SECONDS if target_zoom > zoom else ZOOM_OUT_SECONDS
        zoom = lerpf(zoom, target_zoom, 1.0 - exp(-delta * 3.0 / seconds))
    camera.zoom = Vector2.ONE * zoom
    boat.scale = Vector2.ONE * BOAT_SCALE / zoom

    var zoomed_in := clampf((zoom - 1.0) / (ChartZoom.MAX_CROWDED - 1.0), 0.0, 1.0)
    var half := minf(size.x, size.y) * 0.5 / zoom
    var ahead := Vector2.UP.rotated(boat.heading) * half * LOOK_AHEAD * zoomed_in
    camera.position = boat.position + ahead
    if snap:
        camera.reset_smoothing()
    _keep_clear(boat)


## Where the boat stands on the screen of this view: the rectangle it covers
## (see SeaBoat.footprint).
func boat_rect(boat: SeaBoat) -> Rect2:
    var at := (boat.global_position - camera.get_screen_center_position()) * zoom + size * 0.5
    var footprint := SeaBoat.footprint(boat.heading, boat.ship.length if boat.ship != null else 1.0)
    return Rect2(footprint.position + at, footprint.size)


## Move the panels of the HUD off the boat (see HudDodge): they jump to their
## slots at once, since a panel on its way would cross the others, and hide
## while no slot is free.
func _keep_clear(boat: SeaBoat) -> void:
    var idle: Array[bool] = []
    for panel in _dodgers:
        idle.append(panel == hint and not hint.showing())
    slots = HudDodge.dodge(homes, slots, boat_rect(boat), Rect2(Vector2.ZERO, size), reserved, idle)
    for i in range(_dodgers.size()):
        var hidden := slots[i] == HudDodge.HIDDEN
        _dodgers[i].visible = not hidden
        if not hidden:
            _dodgers[i].position = slots[i].position

class_name MissionScreen
extends Node

## Play a mission (see DESIGN.md, section 4 and section 15): sail the chart of
## the Adriatic, steered with the bird dog, and follow the story of the mission
## from port to port.
##
## Every player steers a boat of their own and has a half of the screen (see
## SeaView), as in ergo-chaos; the webcam sits between the halves with a line
## down its middle. The boats sail on their own: the player who enters a port
## sees its scene in their half, while the other sails on. Every boat has its
## own hold (food and water, the hull, ducats, cargo and passengers); when the
## boats meet at sea, the crews can exchange what they carry. Sailing close
## together, both boats sail faster, and the corsairs keep away.
##
## The chart points to the port where the crew has to go. The food and the
## water run out with the days, and every port fills them again.
##
## The mission's steps decide what happens (see MissionStep and MissionRun);
## this screen sails the boats, shows the scenes of the steps in the ports,
## and shows the stars at the end. It holds the state of the screen, saves the
## mission in progress and lets the boats meet at sea; MissionBuilder builds
## it, MissionStory shows the scenes, and MissionSailing sails the boats.
##
## Without a camera, A/D (the first boat) and the arrow keys (the second boat)
## steer. Esc goes back to the missions.

## Arriving closer than this to a port enters it, in kilometres.
const ENTER_KM := 5.0

## After leaving a port, a boat has to sail this far away before it can enter
## the port again, in kilometres.
const LEAVE_KM := 9.0

## Sailing this far takes a day of the mission clock, in kilometres.
const KM_PER_DAY := 100.0

## Two boats closer than this sail together, and faster, in kilometres.
const TOGETHER_KM := 8.0
const TOGETHER_BOOST := 1.25

## Two boats closer than this meet and can exchange what they carry; they meet
## again only after they were farther apart than PART_KM.
const MEET_KM := 4.0
const PART_KM := 14.0

## The damage of the hull when a boat runs onto a reef at full speed, and onto
## a cliff (out of 100). The rest of the coast never hurts the hull: it would
## be too frustrating.
const REEF_DAMAGE := 35.0
const CLIFF_DAMAGE := 25.0

## Towing a boat to a port is slower than sailing by this factor, and costs
## this many days on top.
const TOW_SLOWER := 2.0
const TOW_DAYS := 0.5

## The fishermen tow a boat at this share of the best speed of a boat: slowly,
## so that the crew watches (see TowBoat).
const TOW_SHARE := 0.45

## New sails make the boats this much faster.
const NEW_SAILS := 1.2

## The colours of the captains: the pennants, the stripes and the frames.
const COLORS: Array[Color] = [Color(0.7, 0.12, 0.1), Color(0.12, 0.32, 0.65)]

## The mission to play; empty takes the mission the crew chose.
@export var mission_id := ""

## How many players sail; 0 takes the crew's.
@export_range(0, 2) var players := 0

## The scene after the mission; empty to play it again (for the test screens).
@export_file("*.tscn") var next_scene := "res://scenes/mission_select/mission_select.tscn"

## Whether to record the stars in the voyage (the test screens do not).
@export var record_result := true

## The port to start in instead of the mission's own (for the test screens,
## e.g., to sail among the islands right away); empty for the mission's own.
@export var start_port_id := ""

var _run: MissionRun
var _wind: SeaWind
var _mission: Mission
var _helms: Array[Helm] = []
var _views: Array[SeaView] = []
var _cards: Array[StoryCard] = []

## Per player: the port where the boat is (null at sea), the port it left last
## (it may enter it again only after sailing away), whether a scene is open in
## its half, the scene of the port which the merchant's stall interrupted, and
## the step of the open scene.
var _in_port: Array = []
var _left: Array = []
var _busy: Array[bool] = []
var _port_scenes: Array = []
var _scene_steps: Array = []

## Per player: the errand which the local of the port offers.
var _offers: Array = []

## Per player: the boosters on the merchant's stall of the port (a random
## four of all, see [method _draw_stall]).
var _stalls: Array = []

## Per player: the Tow to a port, while fishermen tow the boat, or null.
var _tows: Array = []

## Per player: whether the crew was told that the food runs low on this leg.
var _warned_low: Array[bool] = []

var _entry_headings := {}  # By player: the heading of the boat into its last port.

## Whether everything stops for a screen of both players (the briefing, the
## meeting at sea, the end).
var _all_paused := true

## Whether the boats met and have not parted since (they start together).
var _met := true
var _stars := 0

var _chart: ChartView
var _race: RaceCourse
var _rope: Line2D
var _hazards: SeaHazards
var _wheel: WheelPanel
var _overlay: CanvasLayer
var _shared_card: StoryCard
var _shared_cursor: HandCursor
var _exchange: ExchangeCard
var _sfx: Sfx

var _tips: Tips
var _story: MissionStory
var _sailing: MissionSailing

## The question whether to leave the mission (Esc), while it is open.
var _leave_dialog: ConfirmDialog
var _paused_before := false
var _full_chart: FullChart

@onready var _session: Node = get_node("/root/Session")
@onready var _crew: Node = get_node("/root/Crew")
@onready var _pose: Node = get_node("/root/Vision").poses


func _ready() -> void:
    var chosen := mission_id if mission_id != "" else str(_session.current_mission)
    _mission = MissionCatalog.by_id(chosen)
    if _mission == null or not _mission.is_playable():
        _mission = MissionCatalog.all()[0]
    _mission = _mission.starting_in(start_port_id)
    if players <= 0:
        players = _crew.players
    _pose.SetPlayerCount(players)

    var seed_value := randi()
    var ships: Array = []
    for i in range(players):
        ships.append(World.captain_ship(_crew.captains[i]) if i < _crew.captains.size() else null)
    _run = MissionRun.new(_mission, seed_value, players, ships)
    _run.bring(_session.ducats)  # All on board; a mission in progress restores its own.
    _wind = SeaWind.new(_mission.sea, seed_value + 1)
    _story = MissionStory.new(self)
    _sailing = MissionSailing.new(self)
    _run.finished.connect(_story.on_finished)
    _run.rewarded.connect(_story.on_rewarded)

    for i in range(players):
        _in_port.append(_mission.start_port)
        _left.append(_mission.start_port)
        _busy.append(false)
        _port_scenes.append({})
        _scene_steps.append(null)
        _offers.append({})
        _stalls.append([])
        _tows.append(null)
        _warned_low.append(false)

    MissionBuilder.build(self)
    MissionBuilder.launch(self, _mission.start_port, -1)
    if record_result and _session.resume_mission and _session.progress_of() == _mission.id:
        _session.resume_mission = false
        if _restore(_session.mission_in_progress):
            _sailing.place_boats(true)
            _story.resume_all()
            return
    _sailing.place_boats(true)

    # NOTE (mristin):
    # The briefing is for the whole crew, on the whole screen.
    _run.begin()
    var opening: Variant = _run.step().opening(_run)
    if opening != null:
        _story.show_shared(opening, _mission.start_port)
    else:
        _story.resume_all()


func _process(delta: float) -> void:
    _sailing.process(delta)


func _unhandled_input(event: InputEvent) -> void:
    _sailing.unhandled_input(event)


## The steering of a player (the soak test wanders instead, see Helm.read_steer).
func _steer_of(player: int, poses: Array) -> float:
    return Helm.read_steer(player, poses)


## Show a message to the player (or, with -1, to everybody).
func _say(text: String, player: int) -> void:
    for view in _views:
        if player < 0 or view.player == player or players == 1:
            view.toast.show_text(text)


# region Saving


## Save the mission in progress into the voyage (in every port, and when the
## crew leaves the mission), so that the crew can continue it later.
func _save_progress() -> void:
    if not record_result or _run.is_done():
        return
    var boats: Array = []
    for helm in _helms:
        boats.append(helm.to_data(_left[helm.player]))
    _session.mission_in_progress = {
        "run": _run.to_data(),
        "boats": boats,
        "visited": _views[0].minimap.visited.keys(),
    }
    _session.save()


## Continue the mission in progress; return whether it worked. A mission of
## two boats never continues with one, and vice versa.
func _restore(data: Dictionary) -> bool:
    if data.get("boats", []).size() != players:
        return false
    if not _run.restore(data.get("run", {})):
        return false
    var boats: Array = data.get("boats", [])
    for i in range(mini(boats.size(), _helms.size())):
        _in_port[i] = null
        _left[i] = _helms[i].restore(boats[i])
    for port_id in data.get("visited", []):
        var port := World.port(str(port_id))
        if port != null:
            for view in _views:
                view.minimap.visited[port.id] = true
    return true


# endregion

# region Meeting at sea


func _check_meeting() -> void:
    if players < 2 or _busy[0] or _busy[1]:
        return
    var distance := _helms[0].km.distance_to(_helms[1].km)
    if distance > PART_KM:
        _met = false
    if _met or distance > MEET_KM:
        return
    _met = true
    _all_paused = true
    for view in _views:
        view.show_hud(false)
    _exchange = ExchangeCard.new()
    _exchange.run = _run
    var names: Array[String] = []
    for i in range(players):
        var name := str(_crew.captains[i].get("name", "")) if i < _crew.captains.size() else ""
        names.append(name if name != "" else tr("Player {number}").format({"number": i + 1}))
    _exchange.names = names
    _exchange.action_chosen.connect(_on_exchange)
    _overlay.add_child(_exchange)
    _exchange.refresh()
    _overlay.move_child(_shared_cursor, -1)
    _shared_cursor.visible = true


func _on_exchange(action: String) -> void:
    if action == "close":
        _exchange.queue_free()
        _exchange = null
        _shared_cursor.visible = false
        _story.resume_all()
        return
    ExchangeCard.hand_over(_run, action)
    _exchange.refresh()

# endregion

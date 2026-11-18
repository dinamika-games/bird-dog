extends SceneTree
## Check the voyages: a new voyage is saved and listed with its captains and
## stars, the missions unlock one after the other, the best stars are kept,
## every chapter keeps the possessions of its own, a voyage loads again as it
## was saved, and an old save is backed up before it is converted.
##
## The test uses its own directory for the saves, never the players' saves.

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if condition:
        print("PASS ", message)
    else:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


func _make_session(directory: String) -> Node:
    var session: Node = load("res://scenes/session/session.gd").new()
    session.name = "TestSession"
    session.saves_dir = directory
    session.settings_path = directory + "/settings.cfg"
    root.add_child(session)
    return session


func _run() -> void:
    var directory := "user://test_saves_%d" % Time.get_ticks_usec()

    # NOTE (mristin):
    # The session uses the Crew autoload, which Godot loads for the test
    # scripts, too.
    var crew: Node = root.get_node("Crew")

    var session := _make_session(directory)
    await process_frame

    var missions := MissionCatalog.all()
    _check(missions.size() == 35, "there are thirty-five missions")
    for i in range(missions.size()):
        _check(missions[i].number == i + 1, "the missions are in order (%d)" % (i + 1))
    _check(missions[-1].finale, "the last mission is the finale")

    # NOTE (mristin):
    # Three chapters of 15, 10 and 10 missions, each ending in its finale, in
    # the order of the numbers.
    var chapters := MissionCatalog.chapters()
    _check(chapters.size() == 3, "there are three chapters")
    var sizes := [15, 10, 10]
    var previous := 0
    for chapter in chapters:
        var of_chapter := MissionCatalog.of_chapter(chapter.number)
        _check(
            of_chapter.size() == sizes[chapter.number - 1],
            "chapter %d has %d missions" % [chapter.number, sizes[chapter.number - 1]]
        )
        _check(of_chapter[-1].finale, "chapter %d ends in its finale" % chapter.number)
        _check(of_chapter[0].number == previous + 1, "chapter %d follows on" % chapter.number)
        _check(
            MissionCatalog.number_in_chapter(of_chapter[0]) == 1,
            "chapter %d starts with its mission 1" % chapter.number
        )
        for mission in of_chapter.slice(0, -1):
            _check(not mission.finale, "%s is no finale" % mission.id)
        previous = of_chapter[-1].number

    crew.start(2)
    crew.captains[0]["name"] = "Ana"
    session.start("Test voyage")
    _check(session.voyage_name == "Test voyage", "the voyage keeps its name")

    var voyages: Array[Dictionary] = session.list()
    _check(voyages.size() == 1, "the new voyage is saved and listed")
    _check(Array(voyages[0]["captains"]) == ["Ana", "Mare"], "the list shows the captains")
    _check(session.last_id() == session.id, "the new voyage is the last one")

    _check(session.is_unlocked(missions[0]), "the first mission is unlocked")
    _check(not session.is_unlocked(missions[1]), "the second mission is locked")

    _check(session.ducats == 40, "a new voyage starts with 40 ducats")
    session.complete(missions[0].id, 2, 70)
    _check(session.ducats == 70, "the crew keeps the ducats left on board after the mission")
    _check(session.is_unlocked(missions[1]), "finishing a mission unlocks the next one")
    _check(not session.is_unlocked(missions[2]), "but not the one after it")
    _check(not session.is_unlocked(missions[15]), "chapter 2 is locked at first")
    session.complete(missions[14].id, 1)
    _check(session.is_unlocked(missions[15]), "the finale of chapter 1 opens chapter 2")
    _check(not session.is_unlocked(missions[25]), "but not chapter 3")
    session.complete(missions[0].id, 1)
    _check(session.stars(missions[0].id) == 2, "the best stars are kept")
    _check(session.ducats == 70, "the stars pay nothing")
    _check(session.yatak_gift(missions[1].id) == 20, "the yataks collect 20 ducats in a mission")
    _check(session.yatak_gift(missions[1].id) == 0, "but only once per mission")
    _check(session.ducats == 90, "the yataks' ducats count for the voyage at once")
    _check(session.list()[0]["stars"] == 3, "the list counts the stars (2 + 1)")

    # NOTE (mristin):
    # A save of format 1 kept a chest at home; its ducats go on board of the
    # boats of the mission in progress (a boat could overspend from the chest).
    var old := {
        "format": 1,
        "ducats": 249,
        "mission_in_progress":
        {"run": {"holds": [{"ducats": 10, "spent": 90}, {"ducats": 21, "spent": 0}]}},
    }
    var upgraded: Dictionary = session.get_script().upgrade(old)
    var holds: Array = upgraded["mission_in_progress"]["run"]["holds"]
    _check(upgraded["format"] == 3, "an old save is upgraded")
    _check(
        holds[0]["ducats"] == 95 and holds[1]["ducats"] == 95 and holds[0]["spent"] == 0,
        "the chest of an old save goes on board of the boats"
    )
    _check(
        upgraded["chapters"]["1"]["ducats"] == 249,
        "and stays the ducats of the voyage between missions"
    )
    var two := MissionRun.new(missions[0], 1, 2)
    two.bring(41)
    _check(
        two.hold(0).on_board() == 21 and two.hold(1).on_board() == 20 and two.brought == 41,
        "a mission takes all the ducats on board, split between the boats"
    )

    var saved_id: String = session.id
    session.free()
    crew.start(1)
    var reloaded := _make_session(directory)
    await process_frame
    _check(reloaded.load_voyage(saved_id), "the voyage loads again")
    _check(reloaded.voyage_name == "Test voyage", "with its name")
    _check(crew.players == 2 and crew.captains[0]["name"] == "Ana", "with its crew")
    _check(reloaded.is_unlocked(missions[1]), "with its missions")
    _check(reloaded.ducats == 90, "with its ducats")
    _check(not reloaded.has_shipyard(), "the shipyard opens only after mission 2")
    var sail: Decoration = World.decoration("sail_blue")
    _check(sail != null and sail.slot == "sail", "the shipyard has sails")
    _check(reloaded.buy_decoration(sail), "the crew buys a blue sail")
    _check(reloaded.ducats == 90 - sail.price, "the sail costs ducats of the crew")
    _check(not reloaded.buy_decoration(sail), "what is bought stays bought, and is not sold twice")
    crew.captains[0]["boat"] = {"sail": sail.id}
    reloaded.save()
    _check(reloaded.load_voyage(saved_id), "the voyage loads again with the decorations")
    _check(reloaded.owned.has(sail.id), "the crew still owns the sail")
    _check(
        World.boat_decorations(crew.captains[0]).get("sail") == sail,
        "and the captain's boat still wears it"
    )
    _check(not reloaded.load_voyage("missing"), "a missing voyage does not load")
    _check_chapters(reloaded, crew, saved_id, sail)
    _check_upgrade(reloaded, crew, directory)

    reloaded.delete_voyage(saved_id)
    _check(reloaded.list().is_empty(), "a deleted voyage is gone from the list")
    _check(reloaded.last_id() == "", "a deleted voyage is not the last one any more")
    _check(not reloaded.load_voyage(saved_id), "a deleted voyage does not load")

    var name_text: String = reloaded.default_name()
    _check(
        name_text.length() == 16 and name_text[4] == "-", "the default name is the date and time"
    )

    var backups: String = directory + "/" + reloaded.BACKUPS
    for file in DirAccess.get_files_at(backups):
        DirAccess.remove_absolute(backups + "/" + file)
    DirAccess.remove_absolute(backups)
    for file in DirAccess.get_files_at(directory):
        DirAccess.remove_absolute(directory + "/" + file)
    DirAccess.remove_absolute(directory)

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)


## Every chapter starts anew with 40 ducats and the gajeta, and keeps its own
## possessions when the crew comes back to it, also after loading.
func _check_chapters(session: Node, crew: Node, voyage_id: String, sail: Decoration) -> void:
    var gajeta: Ship = World.ships()[0]
    var bracera: Ship = World.ships()[1]
    session.ducats = 500
    _check(session.buy_ship(bracera), "the crew buys a bracera in chapter 1")
    crew.captains[0]["ship"] = bracera.id
    var kept: int = session.ducats

    _check(session.enter_chapter(2), "the crew enters chapter 2 for the first time")
    _check(session.chapter == 2, "and holds the possessions of chapter 2")
    _check(session.ducats == 40, "chapter 2 starts with 40 ducats")
    _check(session.owned.is_empty(), "and nothing bought")
    _check(
        World.captain_ship(crew.captains[0]) == gajeta,
        "the captain sails the gajeta again in chapter 2"
    )
    _check(World.boat_decorations(crew.captains[0]).is_empty(), "without decorations")
    _check(not session.enter_chapter(2), "entering the same chapter again changes nothing")
    session.ducats = 55

    _check(not session.enter_chapter(1), "the crew comes back to chapter 1")
    _check(session.ducats == kept, "chapter 1 kept its ducats")
    _check(
        session.owned.has(sail.id) and session.owned.has(bracera.id),
        "chapter 1 kept what was bought"
    )
    _check(World.captain_ship(crew.captains[0]) == bracera, "and the bracera of the captain")
    _check(
        World.boat_decorations(crew.captains[0]).get("sail") == sail,
        "and the decorations of the boat"
    )
    _check(not session.enter_chapter(2) and session.ducats == 55, "chapter 2 kept its ducats")

    _check(session.load_voyage(voyage_id), "the voyage loads with its chapters")
    _check(session.chapter == 2 and session.ducats == 55, "in the chapter which the crew left")
    _check(
        not session.enter_chapter(1) and session.ducats == kept, "with the possessions of chapter 1"
    )
    _check(World.captain_ship(crew.captains[0]) == bracera, "and its boats")


## A save of format 2 carried the possessions over the chapters: they stay with
## the chapter which the crew plays, and the save is backed up before it is
## converted.
func _check_upgrade(session: Node, crew: Node, directory: String) -> void:
    var states := {}
    for mission in MissionCatalog.of_chapter(1):
        states[mission.id] = {"completed": true, "stars": 1, "gifted": true}
    var old := {
        "format": 2,
        "id": "old-voyage",
        "name": "Old voyage",
        "created": "2026-11-01T10:00:00",
        "updated": "2026-11-01T11:00:00",
        "crew":
        {
            "players": 1,
            "captains": [{"name": "Ana", "ship": "bracera", "boat": {"streamers": "streamers"}}]
        },
        "missions": states,
        "ducats": 321,
        "owned": ["bracera", "streamers"],
        "mission_in_progress": {},
        "hints_seen": [],
    }
    var text := JSON.stringify(old, "  ")
    var file := FileAccess.open(directory + "/old-voyage.json", FileAccess.WRITE)
    file.store_string(text)
    file.close()

    _check(session.load_voyage("old-voyage"), "a voyage of format 2 loads")
    _check(session.chapter == 2, "in the chapter which the crew plays")
    _check(session.ducats == 321, "with its ducats")
    _check(session.owned.has("bracera"), "and what was bought")
    _check(World.captain_ship(crew.captains[0]).id == "bracera", "and the ship of the captain")
    var backup: String = "%s/%s/old-voyage.format2.json" % [directory, session.BACKUPS]
    _check(
        FileAccess.get_file_as_string(backup) == text, "the save of format 2 is backed up as it was"
    )
    var saved: Dictionary = JSON.parse_string(
        FileAccess.get_file_as_string(directory + "/old-voyage.json")
    )
    _check(int(saved["format"]) == 3, "the save is converted to format 3")
    _check(
        not saved.has("ducats") and saved["chapters"].has("2"), "with the possessions by chapter"
    )
    _check(session.enter_chapter(1), "chapter 1 starts anew in the converted voyage")
    _check(session.ducats == 40, "with 40 ducats")
    session.delete_voyage("old-voyage")

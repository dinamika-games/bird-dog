class_name HudDodge
extends RefCounted

## The HUD never covers the player's own boat (see DESIGN.md, "The HUD keeps
## clear of the boat"). Every panel has its home in the layout; when the boat
## comes under it, the panel moves elsewhere, and comes back once the boat
## sailed on.
##
## A panel moves only to a slot clear of the boat, of the reserved places (the
## webcam) and of the other panels, inside the view. It prefers the edges of
## the view (its home moved to the left or the right edge, to the top or the
## bottom, or both), so that it does not wander after the boat, and takes a
## slot right beside the boat only if no slot at the edges will do; of those, it
## takes the one nearest its home; failing that, it takes the nearest free
## place on a grid over the view. If no place will do at all (which hardly ever
## happens), the panel hides (its slot is [constant HIDDEN]) until the boat
## sails on.

## The panels leave as the boat comes this close (in pixels), so that they are
## gone before it arrives...
const LEAVE_MARGIN := 8.0

## ...and come back home only when the boat is this far, so that they do not
## jump back and forth at the edge.
const RETURN_MARGIN := 48.0

## The slots keep this gap to the edge of the view.
const EDGE := 12.0

## The slot of a panel which hides, since no slot is free.
const HIDDEN := Rect2()

## The step of the grid of the slots of the last resort (see [method grid]).
const GRID := 24.0

static var _grids := {}


## Where the panels should stand: [param homes] are their places in the layout,
## [param current] where they stand now, [param boat] the rectangle of the boat
## on the screen (see [method SeaBoat.footprint]), [param view] the rectangle of
## the view, and [param reserved] the places no panel may go to. The homes
## must neither overlap each other nor the reserved places. The panels which
## show nothing now (e.g., the tips between two tips) are [param idle]: they
## stay at home and take no place.
static func dodge(
    homes: Array[Rect2],
    current: Array[Rect2],
    boat: Rect2,
    view: Rect2,
    reserved: Array[Rect2],
    idle: Array[bool] = []
) -> Array[Rect2]:
    var near := boat.grow(LEAVE_MARGIN)
    var far := boat.grow(RETURN_MARGIN)
    var result: Array[Rect2] = current.duplicate()
    var taken: Array[Rect2] = reserved.duplicate()

    # NOTE (mristin):
    # The panels which may go home claim their places first, then the panels
    # which can stay where they are, and the rest move around them.
    var staying: Array[int] = []
    var moving: Array[int] = []
    for i in range(homes.size()):
        if i < idle.size() and idle[i]:
            result[i] = homes[i]
        elif not homes[i].intersects(far):
            result[i] = homes[i]
            taken.append(homes[i])
        elif current[i].has_area() and not current[i].intersects(near):
            staying.append(i)
        else:
            moving.append(i)
    for i in staying:
        if _hits(current[i], taken):
            moving.append(i)
        else:
            taken.append(current[i])

    # NOTE (mristin):
    # The large panels find their places first; the small ones fit in between.
    moving.sort_custom(
        func(a: int, b: int) -> bool: return homes[a].get_area() > homes[b].get_area()
    )
    for i in moving:
        result[i] = HIDDEN
        for slot in slots(homes[i], view) + beside(homes[i], near, view):
            if not slot.intersects(near) and not _hits(slot, taken):
                result[i] = slot
                break
        if result[i] == HIDDEN:
            for slot in grid(homes[i], view):
                if not slot.intersects(near) and not _hits(slot, taken):
                    result[i] = slot
                    break
        if result[i] != HIDDEN:
            taken.append(result[i])
    return result


## The slots at the edges of [param view] where the panel of [param home] may
## stand: its home, and its home moved to the edges, the nearest ones first.
static func slots(home: Rect2, view: Rect2) -> Array[Rect2]:
    var xs: Array[float] = [
        home.position.x, view.position.x + EDGE, view.end.x - EDGE - home.size.x
    ]
    var ys: Array[float] = [
        home.position.y, view.position.y + EDGE, view.end.y - EDGE - home.size.y
    ]
    var result: Array[Rect2] = []
    for x in xs:
        for y in ys:
            var slot := Rect2(Vector2(x, y), home.size)
            if not result.has(slot):
                result.append(slot)
    return _nearest_first(result, home)


## The slots right beside the boat [param near] where the panel of
## [param home] may stand: to the left or the right of the boat, above or below
## it, or both, at the height or the side of its home or at the edges; only
## those in [param view], the nearest ones first.
static func beside(home: Rect2, near: Rect2, view: Rect2) -> Array[Rect2]:
    var inner := view.grow(-EDGE)
    var xs: Array[float] = [
        home.position.x,
        inner.position.x,
        inner.end.x - home.size.x,
        near.position.x - home.size.x,
        near.end.x,
    ]
    var ys: Array[float] = [
        home.position.y,
        inner.position.y,
        inner.end.y - home.size.y,
        near.position.y - home.size.y,
        near.end.y,
    ]
    var result: Array[Rect2] = []
    for x in xs:
        for y in ys:
            var slot := Rect2(Vector2(x, y), home.size)
            if inner.encloses(slot) and not result.has(slot):
                result.append(slot)
    return _nearest_first(result, home)


## The slots on a grid over [param view] (every [constant GRID] pixels) where
## the panel of [param home] may stand, the nearest ones first: the last resort
## when neither the edges nor the places beside the boat are free. They are
## computed once for every home.
static func grid(home: Rect2, view: Rect2) -> Array[Rect2]:
    var key := "%s %s" % [home, view]
    if _grids.has(key):
        return _grids[key]
    var inner := view.grow(-EDGE)
    var result: Array[Rect2] = []
    var x := inner.position.x
    while x + home.size.x <= inner.end.x:
        var y := inner.position.y
        while y + home.size.y <= inner.end.y:
            result.append(Rect2(Vector2(x, y), home.size))
            y += GRID
        x += GRID
    _grids[key] = _nearest_first(result, home)
    return result


static func _nearest_first(rects: Array[Rect2], home: Rect2) -> Array[Rect2]:
    rects.sort_custom(
        func(a: Rect2, b: Rect2) -> bool:
            return a.position.distance_to(home.position) < b.position.distance_to(home.position)
    )
    return rects


static func _hits(rect: Rect2, others: Array[Rect2]) -> bool:
    for other in others:
        if rect.intersects(other):
            return true
    return false

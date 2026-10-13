import common

proc less(a, b: SpatialEntry): bool {.inline, raises: [].} =
  ## Orders fixed coordinates with stable IDs for equal X positions.
  a.x < b.x or (a.x == b.x and a.id < b.id)

proc sift(
    entries: var array[MaxBodies, SpatialEntry], first, count, offset: int
) =
  ## Restores one maximum heap without temporary sequences or closures.
  var root = first
  while root * 2 + 1 < count:
    var child = root * 2 + 1
    if child + 1 < count and
      entries[offset + child].less(entries[offset + child + 1]):
      inc child
    if not entries[offset + root].less(entries[offset + child]):
      break
    swap(entries[offset + root], entries[offset + child])
    root = child

proc sortAxis*(world: World, count: int) =
  ## Builds an X-sorted fixed-point index in O(N log N) with no allocations.
  world.sortedCounts = [0, 0]
  for i in 0 ..< count:
    inc world.sortedCounts[world.bodies[world.activeBodies[i].int].kind]
  var next: array[BodyKind, int] = [0, world.sortedCounts[PlanetBody]]
  for i in 0 ..< count:
    let id = world.activeBodies[i]
    let group = world.bodies[id.int].kind
    world.sorted[next[group]] = SpatialEntry(x: world.spatialX[id.int], id: id)
    inc next[group]
  for group in BodyKind:
    let
      offset = if group == PlanetBody: 0 else: world.sortedCounts[PlanetBody]
      length = world.sortedCounts[group]
    for i in countdown(length div 2 - 1, 0):
      world.sorted.sift(i, length, offset)
    for last in countdown(length - 1, 1):
      swap(world.sorted[offset], world.sorted[offset + last])
      world.sorted.sift(0, last, offset)

proc firstInRange*(world: World, start, count: int, left: int64): int =
  ## Finds the first candidate X coordinate by binary search.
  var
    low = start
    high = start + count
  while low < high:
    let middle = (low + high) div 2
    if world.sorted[middle].x.int64 < left:
      low = middle + 1
    else:
      high = middle
  low

proc cell*(coordinate: int64, size, count: int): int {.inline.} =
  ## Folds outside coordinates into edge buckets without dropping bodies.
  clamp(coordinate div (size.int64 * FixedScale), 0, (count - 1).int64).int

proc buildGrid*(world: World, count, size: int) =
  ## Reuses dense cell heads and linked body indices for one tick snapshot.
  let
    columns = (Width + size - 1) div size
    rows = (Height + size - 1) div size
  for i in 0 ..< columns * rows:
    world.gridHeads[i] = 0
    world.gridPlanetHeads[i] = 0
  for i in 0 ..< count:
    let
      id = world.activeBodies[i].int
      x = cell(world.spatialX[id].int64, size, columns)
      y = cell(world.spatialY[id].int64, size, rows)
      index = y * columns + x
    if world.bodies[id].kind == PlanetBody:
      world.gridNext[id] = world.gridPlanetHeads[index]
      world.gridPlanetHeads[index] = (id + 1).uint16
    else:
      world.gridNext[id] = world.gridHeads[index]
      world.gridHeads[index] = (id + 1).uint16

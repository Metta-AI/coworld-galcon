import
  flatty, polyworld/tapes,
  common, worlds, profiles

const
  ReplayVersion* = 3'u16
  MaxTicks* = TickRate * 60 * 30
  MaxOrders* = 1_000_000

type
  LegacySetup = object
    seed: int32
    difficulty: Difficulty
    tutorial: int
    counts: array[3, int]
  LegacyRecording = object
    setup: LegacySetup
    orders: seq[Order]
    hashes: seq[uint64]
  SetupData = object
    ## Version 2 wire fields remain values to preserve existing replay bytes.
    seed: int32
    difficulty: Difficulty
    tutorial: int
    players: int
    counts: seq[int]
  RecordingData = object
    ## Serialized fields are assembled only at the file boundary.
    setup: SetupData
    orders: seq[Order]
    hashes: seq[uint64]
  SpatialRecordingData = object
    setup: SetupData
    collisions: CollisionKind
    orders: seq[Order]
    hashes: seq[uint64]
  Recording* = ref object
    setup*: Setup
    orders*: seq[Order]
    hashes*: seq[uint64]

proc recordTick*(recording: Recording, world: World) {.measure.} =
  ## Appends bounded orders and the resulting state hash for one tick.
  if recording.hashes.len >= MaxTicks:
    raise newException(GalconError, "Replay exceeds the 30-minute limit")
  for order in world.orders:
    if recording.orders.len >= MaxOrders:
      raise newException(GalconError, "Replay has too many orders")
    recording.orders.add order
  world.orders.setLen(0)
  recording.hashes.add world.fingerprint()

proc save*(recording: Recording, path: string) =
  ## Writes a replay using Polyworld's versioned portable file format.
  try:
    let data = SpatialRecordingData(
      setup: SetupData(
        seed: recording.setup.seed,
        difficulty: recording.setup.difficulty,
        tutorial: recording.setup.tutorial,
        players: recording.setup.players,
        counts: recording.setup.counts
      ),
      collisions: recording.setup.collisions,
      orders: recording.orders,
      hashes: recording.hashes
    )
    saveReplayFile(path, "galcon", ReplayVersion, data)
  except IOError, OSError, ReplayError:
    raise newException(
      GalconError,
      "Cannot save replay: " & getCurrentExceptionMsg()
    )

proc loadRecording*(path: string): Recording =
  ## Validates a Polyworld Galcon replay before starting playback.
  try:
    result = Recording()
    let
      bytes = readFile(path)
      header = bytes.replayFileHeader()
    if header.gameVersion == 1:
      let legacy = decodeReplayFile("galcon", 1, bytes, LegacyRecording)
      result.setup = Setup(
        seed: legacy.setup.seed,
        difficulty: legacy.setup.difficulty,
        tutorial: legacy.setup.tutorial,
        players: 2,
        collisions: AllPairs,
        counts: @(legacy.setup.counts)
      )
      result.orders = legacy.orders
      result.hashes = legacy.hashes
    elif header.gameVersion == 2:
      let data = decodeReplayFile("galcon", 2, bytes, RecordingData)
      result.setup = Setup(
        seed: data.setup.seed,
        difficulty: data.setup.difficulty,
        tutorial: data.setup.tutorial,
        players: data.setup.players,
        collisions: AllPairs,
        counts: data.setup.counts
      )
      result.orders = data.orders
      result.hashes = data.hashes
    else:
      let data = decodeReplayFile(
        "galcon", ReplayVersion, bytes, SpatialRecordingData
      )
      result.setup = Setup(
        seed: data.setup.seed,
        difficulty: data.setup.difficulty,
        tutorial: data.setup.tutorial,
        players: data.setup.players,
        collisions: data.collisions,
        counts: data.setup.counts
      )
      result.orders = data.orders
      result.hashes = data.hashes
  except IOError, OSError, ReplayError, ValueError, FlattyError, IndexDefect:
    raise newException(
      GalconError,
      "Cannot load replay: " & getCurrentExceptionMsg()
    )
  if result.hashes.len > MaxTicks or result.orders.len > MaxOrders:
    raise newException(GalconError, "Replay limits exceeded")
  let world = newWorld(result.setup)
  var previous = -1'i32
  for order in result.orders:
    if order.tick < 0 or order.tick < previous or
      order.tick >= result.hashes.len.int32 or
      order.count <= 0 or order.count > MaxBodies or
      order.player < 1 or order.player > result.setup.players.int32 or
      not world.validPlanet(order.source.int) or
      not world.validPlanet(order.target.int) or order.source == order.target:
        raise newException(GalconError, "Invalid replay order")
    previous = order.tick

proc clone*(recording: Recording): Recording =
  ## Makes an explicit isolated tape copy for edits or validation experiments.
  result = Recording(
    setup: recording.setup.clone(),
    orders: newSeq[Order](recording.orders.len),
    hashes: newSeq[uint64](recording.hashes.len)
  )
  for i, order in recording.orders:
    result.orders[i] = order
  for i, hash in recording.hashes:
    result.hashes[i] = hash

proc replayTick*(recording: Recording, world: World, cursor: var int) =
  ## Applies recorded orders and checks the next deterministic simulation hash.
  if world.tick >= recording.hashes.len.int32:
    return
  let tick = world.tick
  while cursor < recording.orders.len and recording.orders[cursor].tick == tick:
    let order = recording.orders[cursor]
    let sent = world.launch(
      order.player.int,
      order.source.int,
      order.target.int,
      order.count.int
    )
    if sent != order.count.int:
      raise newException(GalconError, "Invalid replay launch at tick " & $tick)
    inc cursor
  world.advance()
  world.orders.setLen(0)
  if world.fingerprint() != recording.hashes[tick]:
    raise newException(GalconError, "Replay diverged at tick " & $tick)

proc orderCursor*(recording: Recording, tick: int32): int =
  ## Finds the first launch at or after a restored checkpoint tick.
  var
    low = 0
    high = recording.orders.len
  while low < high:
    let middle = (low + high) div 2
    if recording.orders[middle].tick < tick:
      low = middle + 1
    else:
      high = middle
  low

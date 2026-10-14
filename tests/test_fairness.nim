import
  std/os,
  polyworld/tapes,
  galcon/[common, worlds, replays]

proc testFairness*() =
  ## Checks equal resources, seeded random starts, and old replay verification.
  echo "Competitive presets give every faction equal planet counts"
  for difficulty in Difficulty:
    for players in [2, 5, MaxPlayers]:
      for count in [players, min(MaxPlanets, players + 3), MaxPlanets]:
        let setup = configuredSetup(8, difficulty, players, count)
        var total = setup.counts[0]
        for owner in 1 .. players:
          doAssert setup.counts[owner] == setup.counts[1]
          total += setup.counts[owner]
        doAssert total == count
  echo "Every color can start in every quadrant and planet slot"
  var
    quadrants: array[MaxPlayers + 1, array[4, bool]]
    slots: array[MaxPlayers + 1, array[26, bool]]
  for seed in 0 ..< 256:
    let world = newWorld(configuredSetup(seed.int32, Easy, 5, 26))
    for i, planet in world.planets:
      if planet.owner == 0:
        continue
      doAssert planet.production == 100
      doAssert planet.shipCount == 100
      doAssert planet.realShips == stock(100)
      doAssert planet.morale == 100
      let quadrant = int(planet.x >= fixed(Width div 2)) +
        2 * int(planet.y >= fixed(Height div 2))
      quadrants[planet.owner][quadrant] = true
      slots[planet.owner][i] = true
  for owner in 1 .. 5:
    for seen in quadrants[owner]:
      doAssert seen
    for seen in slots[owner]:
      doAssert seen
  let
    first = newWorld(configuredSetup(42, Easy, 5, 26))
    repeated = newWorld(configuredSetup(42, Easy, 5, 26))
    different = newWorld(configuredSetup(43, Easy, 5, 26))
  doAssert first.fingerprint() == repeated.fingerprint()
  doAssert first.fingerprint() != different.fingerprint()
  echo "Ratings results contain only victory and defeat"
  first.winner = 3
  doAssert first.scores() == @[0, 0, 1, 0, 0]
  for planet in first.planets:
    planet.ships = stock(1_000_000)
    planet.owner = 1
  doAssert first.scores() == @[0, 0, 1, 0, 0]
  first.winner = 0
  doAssert first.scores() == @[0, 0, 0, 0, 0]
  echo "Version 6 retains its positions and verifies original hashes"
  type
    OriginalSetup = object
      seed: int32
      difficulty: Difficulty
      tutorial: int
      players: int
      counts: seq[int]
    OriginalRecording = object
      setup: OriginalSetup
      collisions: CollisionKind
      orders: seq[Order]
      hashes: seq[uint64]
      chats: seq[ChatMessage]
      names: seq[string]
  let setup = configuredSetup(8, Easy, 5, 26)
  setup.placement = ClassicPlacement
  let world = newWorld(setup)
  var old = OriginalRecording(
    setup: OriginalSetup(seed: 8, players: 5, counts: setup.counts),
    collisions: setup.collisions
  )
  for i in 0 ..< 64:
    world.advance()
    old.hashes.add world.fingerprint()
  let
    path = Root / "build" / "version6.replay"
    upgradedPath = Root / "build" / "version6-upgraded.replay"
  saveReplayFile(path, "galcon", 6, old)
  let loaded = loadRecording(path)
  doAssert loaded.setup.placement == ClassicPlacement
  doAssert loaded.hashes == old.hashes
  let playback = newWorld(loaded.setup)
  var cursor = 0
  for i in 0 ..< loaded.hashes.len:
    loaded.replayTick(playback, cursor)
  doAssert playback.fingerprint() == world.fingerprint()
  loaded.save(upgradedPath)
  let upgraded = loadRecording(upgradedPath)
  doAssert upgraded.setup.placement == ClassicPlacement
  doAssert upgraded.hashes == old.hashes
  doAssert readFile(upgradedPath).replayFileHeader().gameVersion == 7
  removeFile(path)
  removeFile(upgradedPath)

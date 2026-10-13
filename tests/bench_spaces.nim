import
  std/[monotimes, times],
  galcon/[common, physics, worlds, options, sessions]

const
  FirstTick = 8192
  Samples = 512

proc benchmark*() =
  ## Compares collision lookups on identical snapshots from the five-bot match.
  let options = parseOptions(@[
    "--headless", "--players", "5", "--planets", "26", "--seed", "8",
    "--bot", Baseline & ":5", "--minutes", "10"
  ])
  options.setup.collisions = AllPairs
  let session = newSession(options)
  var
    durations: array[CollisionKind, int64]
    checksums: array[CollisionKind, uint64]
    count = 0
  while session.world.tick < FirstTick + Samples:
    if session.world.tick >= FirstTick:
      for offset in 0 ..< ord(high(CollisionKind)) + 1:
        let
          kind = CollisionKind((offset + count) mod
            (ord(high(CollisionKind)) + 1))
          world = session.world.clone()
        when defined(nimTypeNames):
          let before = getMemCounters()
        let started = getMonoTime()
        world.moveBodies(kind)
        durations[kind] += (getMonoTime() - started).inNanoseconds
        when defined(nimTypeNames):
          let after = getMemCounters()
          doAssert after[0] == before[0]
          doAssert after[1] == before[1]
        checksums[kind] = checksums[kind] xor world.fingerprint()
      inc count
    session.step()
  for kind in CollisionKind:
    echo kind, " samples=", count, " totalMs=",
      durations[kind].float64 / 1e6, " microsecondsPerTick=",
      durations[kind].float64 / count.float64 / 1000,
      " checksum=", checksums[kind]

benchmark()

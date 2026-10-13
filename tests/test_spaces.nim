import
  std/os,
  galcon/[common, physics, worlds, options, sessions]

proc testSpaces*() =
  ## Checks spatial contacts, edge buckets, deterministic matches, and replays.
  echo "Spatial lookups handle cell boundaries and outside positions"
  for kind in CollisionKind:
    for position in [-12, 31, 63, 640, 2000]:
      for firstKind in BodyKind:
        for secondKind in BodyKind:
          let world = World(setup: defaultSetup(), winner: -1)
          world.bodies[3] = Body(
            active: true, kind: firstKind, x: fixed(position.int32),
            y: fixed(100), radius: fixed(6), weight: 1, target: -1
          )
          world.bodies[11] = Body(
            active: true, kind: secondKind, x: fixed((position + 5).int32),
            y: fixed(100), radius: fixed(6), weight: 1, target: -1
          )
          world.moveBodies(kind)
          doAssert world.bodies[11].x - world.bodies[3].x == fixed(12)
      let world = World(setup: defaultSetup(), winner: -1)
      world.bodies[3] = Body(
        active: true, kind: ShipBody, x: fixed(position.int32),
        y: fixed(-10), radius: fixed(6), weight: 1, target: 11
      )
      world.bodies[11] = Body(
        active: true, kind: PlanetBody, x: fixed((position + 17).int32),
        y: fixed(-10), radius: fixed(22), weight: 100_000, target: -1
      )
      world.moveBodies(kind)
      doAssert world.bodies[3].hit
  echo "Every spatial strategy records and replays deterministically"
  for kind in CollisionKind:
    let
      path = Root / "build" / ("spatial-" & $kind & ".replay")
      options = parseOptions(@[
        "--headless", "--players", "5", "--planets", "26", "--seed", "8",
        "--ticks", "512", "--record", path
      ])
    options.setup.collisions = kind
    let
      first = newSession(options)
      second = newSession(options)
    while not first.done:
      first.step()
      second.step()
      doAssert first.world.fingerprint() == second.world.fingerprint()
      for planet in first.world.planets:
        doAssert planet.ships >= 0
        for incoming in planet.incoming:
          doAssert incoming >= 0
    for owner in 1 .. 5:
      doAssert not first.brains[owner].failed
    let playback = newSession(parseOptions(@["--headless", "--replay", path]))
    doAssert playback.world.setup.collisions == kind
    playback.seek(first.world.tick)
    doAssert playback.world.fingerprint() == first.world.fingerprint()
    removeFile(path)

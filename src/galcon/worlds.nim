import
  std/algorithm,
  polyworld/rngs,
  common, physics, profiles

proc name(rng: var Rng): string =
  ## Generates pronounceable planet names using the original letter sets.
  const
    Consonants = "bdfgjklmnprstvxz"
    Vowels = "aeiou"
    Letters = Consonants & Vowels
  var character = Letters[rng.below(Letters.len.int32)]
  result.add character
  let count = rng.between(3, 7)
  for i in 0 ..< count:
    let letters = if character in Consonants: Vowels else: Consonants
    character = letters[rng.below(letters.len.int32)]
    result.add character

proc rebuildNeighbors*(world: World) =
  ## Uses the nearest five planets and symmetric links, as in Galcon 2006.
  for i in 0 ..< world.planets.len:
    var distances: seq[tuple[distance: int64, index: int]]
    for j in 0 ..< world.planets.len:
      if i == j:
        continue
      let
        dx = world.planets[j].x - world.planets[i].x
        dy = world.planets[j].y - world.planets[i].y
      distances.add (lengthSquared(dx, dy), j)
    distances.sort()
    world.planets[i].neighbors.setLen(0)
    for j in 0 ..< min(5, distances.len):
      world.planets[i].neighbors.add distances[j].index
  for i in 0 ..< world.planets.len:
    for j in 0 ..< world.planets.len:
      if i in world.planets[j].neighbors and j notin world.planets[i].neighbors:
        world.planets[i].neighbors.add j

proc newWorld*(setup: Setup): World =
  ## Creates and separates the original map with a portable Polyworld seed.
  if setup.players < 1 or setup.players > MaxPlayers or
    setup.counts.len != setup.players + 1:
      raise newException(GalconError, "Map counts must match its player roster")
  var count = 0
  for amount in setup.counts:
    if amount < 0 or amount > MaxPlanets:
      raise newException(
        GalconError,
        "Planet counts must be 0 through " & $MaxPlanets
      )
    count += amount
  if count < 2 or count > MaxPlanets:
    raise newException(
      GalconError,
      "Map must have 2 through " & $MaxPlanets & " planets"
    )
  result = World(
    setup: setup,
    planets: newSeqOfCap[Planet](count),
    orders: newSeqOfCap[Order](MaxBodies),
    rng: initRng(setup.seed),
    effectsRng: initRng(setup.seed, 0x5041525449434c45'u64),
    winner: -1
  )
  for owner in countdown(setup.players, 0):
    for i in 0 ..< setup.counts[owner]:
      let
        production =
          if i == 0 and owner > 0: 100
          else: result.rng.between(1, 100).int
        slot = result.freeBody()
        radius = 12 + production * 10 div 100
      var planet = Planet(
        owner: owner,
        production: production,
        radius: radius,
        body: slot,
        x: fixed(result.rng.between(24, Width - 25)),
        y: fixed(result.rng.between(56, Height - 57)),
        ships: stock(result.rng.between(10, 29).int),
        morale: 50,
        frame: result.rng.between(0, TickRate * 23 - 1),
        textureSeed: result.rng.below(int32.high),
        textureKind: result.rng.between(0, 1)
      )
      planet.name = result.rng.name()
      planet.realShips = planet.ships
      planet.realMorale = 50
      if i == 0 and owner > 0:
        planet.ships = stock(100)
        planet.morale = 100
        if setup.players == 2:
          planet.x = fixed(if owner == 1: 24 else: Width - 24)
        elif setup.players > 2:
          let
            angle = FixedTau * (owner - 1).int32 / setup.players.int32
            centerX = fixed((Width div 2).int32)
            centerY = fixed((Height div 2).int32)
          planet.x = centerX - cos(angle) * fixed(250)
          planet.y = centerY - sin(angle) * fixed(155)
        if setup.tutorial > 0 and owner == 2:
          planet.ships = stock(25)
      result.bodies[slot] = Body(
        active: true,
        kind: PlanetBody,
        x: planet.x,
        y: planet.y,
        radius: fixed((radius + 9).int32),
        weight: 100_000,
        target: -1
      )
      result.planets.add planet
  for i in 0 ..< TickRate:
    for planet in result.planets.mitems:
      let body = addr result.bodies[planet.body]
      planet.x = fixed(clamp(
        body.x.toInt.int,
        8 + planet.radius,
        Width - 8 - planet.radius
      ).int32)
      planet.y = fixed(clamp(
        body.y.toInt.int,
        40 + planet.radius,
        Height - 40 - planet.radius
      ).int32)
      body.x = planet.x
      body.y = planet.y
    result.moveBodies()
  for planet in result.planets.mitems:
    result.bodies[planet.body].radius = fixed(planet.radius.int32)
  result.rebuildNeighbors()

proc validPlanet*(world: World, index: int): bool {.raises: [].} =
  ## Checks one stable planet index at API boundaries.
  index >= 0 and index < world.planets.len

proc launch*(world: World, player, source, target, amount: int): int =
  ## Launches authorized ships without exceeding the original 4096 slots.
  if player < 1 or player > world.setup.players or
    not world.validPlanet(source) or not world.validPlanet(target) or
    source == target or amount <= 0:
      return
  if world.planets[source].owner != player:
    return
  let count = min(amount, world.planets[source].shipCount)
  for i in 0 ..< count:
    let slot = world.freeBody()
    if slot < 0:
      break
    let
      a = world.planets[source]
      b = world.planets[target]
    world.bodies[slot] = Body(
      active: true,
      kind: ShipBody,
      x: a.x,
      y: a.y,
      previousX: a.x,
      previousY: a.y,
      targetX: b.x,
      targetY: b.y,
      target: b.body,
      radius: fixed(6),
      weight: 1,
      speed: FixedOne
    )
    world.ships[slot] = Ship(owner: player, target: target)
    world.planets[source].ships -= stock(1)
    inc world.planets[target].incoming[player]
    inc world.activeShips
    inc result
  if result > 0:
    world.orders.add Order(
      tick: world.tick,
      player: player.int32,
      source: source.int32,
      target: target.int32,
      count: result.int32
    )

proc send*(world: World, player, source, target, percent: int): int =
  ## Sends a bounded percentage of one owned planet's current ships.
  if not world.validPlanet(source):
    return 0
  let amount = roundedRatio(
    world.planets[source].ships * clamp(percent, 0, 100),
    FixedScale * 100
  ).int
  world.launch(player, source, target, amount)

proc explode(world: World, x, y, radius: Fixed, count: int) =
  ## Reuses the original bounded 1024-particle pool and 32-frame fade.
  for i in 0 ..< count:
    inc world.effectCursor
    let
      slot = world.effectCursor mod MaxEffects
      angle = fixed(world.effectsRng.between(0, 359)) * FixedPi / 180
      speed = fixed(world.effectsRng.between(0, 99)) / 100
      bound = max(1, (radius * 100).toInt)
      distance = fixed(world.effectsRng.below(bound)) / 100
      vx = speed * cos(angle)
      vy = speed * sin(angle)
    world.effects[slot] = Effect(
      active: true,
      x: x + distance * vx * cos(angle),
      y: y + distance * vy * sin(angle),
      vx: vx,
      vy: vy,
      frame: world.effectsRng.between(-5, 4).int
    )

proc produce*(world: World) {.measure.} =
  ## Updates neighborhood morale and production before resolving arrivals.
  for p in world.planets.mitems:
    var
      friendly = p.ships + stock(p.incoming[p.owner])
      hostile = -stock(p.incoming[p.owner])
    for owner in 0 .. world.setup.players:
      hostile += stock(p.incoming[owner])
    for index in p.neighbors:
      let neighbor = world.planets[index]
      if neighbor.owner == p.owner:
        friendly += neighbor.ships
      elif neighbor.owner != 0:
        hostile += neighbor.ships
    p.realShips = friendly - hostile
    let total = friendly + hostile
    p.realMorale =
      if total != 0: int(roundedRatio(friendly * 100, total))
      else: 100
    if p.realMorale < p.morale and p.frame mod 2 == 0:
      dec p.morale
    if p.realMorale > p.morale and p.frame mod 8 == 0:
      inc p.morale
    p.morale = clamp(p.morale, 0, 100)
    let growth = roundedRatio(
      p.production.int64 * p.morale * FixedScale,
      160_000
    )
    p.ships = max(0, p.ships + growth)
    inc p.frame

proc advance*(world: World) {.measure.} =
  ## Runs flocking, effects, production, arrivals, and endings in LD8 order.
  if world.winner >= 0:
    return
  world.moveBodies(world.setup.collisions)
  profileBlock "effects":
    for effect in world.effects.mitems:
      if effect.active:
        if effect.frame == 32:
          effect.active = false
        effect.x += effect.vx
        effect.y += effect.vy
        inc effect.frame
  world.produce()
  profileBlock "arrivals":
    for i in 0 ..< MaxBodies:
      let body = addr world.bodies[i]
      if not body.active or body.kind != ShipBody or not body.hit:
        continue
      let
        ship = world.ships[i]
        planet = addr world.planets[ship.target]
      dec planet.incoming[ship.owner]
      if planet.owner == ship.owner:
        planet.ships += stock(1)
      else:
        planet.ships -= stock(1)
        inc world.impacts
        world.explode(body.x, body.y, FixedOne, 16)
        if planet.ships < 0:
          planet.ships = abs(planet.ships)
          planet.owner = ship.owner
          inc world.revision
          inc world.captures
          world.explode(planet.x, planet.y, fixed(planet.radius.int32), 512)
      body.active = false
      dec world.activeShips
  var
    counts: array[MaxPlayers + 1, int]
    initialPlayers = 0
    survivors = 0
    last = 0
  for planet in world.planets:
    inc counts[planet.owner]
  for owner in 1 .. world.setup.players:
    if world.setup.counts[owner] > 0:
      inc initialPlayers
    if counts[owner] > 0:
      inc survivors
      last = owner
  let ended =
    if initialPlayers == 1:
      survivors == 0 or counts[0] == 0
    else:
      survivors <= 1
  if ended:
    inc world.endWait
    if world.endWait == TickRate * 3:
      world.winner = last
  else:
    world.endWait = 0
  inc world.tick

proc scores*(world: World): seq[int] =
  ## Gives the surviving winner one point across the configured roster.
  result = newSeq[int](world.setup.players)
  if world.winner in 1 .. world.setup.players:
    result[world.winner - 1] = 1

proc clone*(world: World): World =
  ## Copies fixed state and mutable sequences for an isolated seek checkpoint.
  result = World()
  result[] = world[]
  result.planets = newSeq[Planet](world.planets.len)
  for i, planet in world.planets:
    result.planets[i] = Planet()
    result.planets[i][] = planet[]
    result.planets[i].neighbors = newSeq[int](planet.neighbors.len)
    for j, neighbor in planet.neighbors:
      result.planets[i].neighbors[j] = neighbor
  result.setup = world.setup.clone()
  result.orders = newSeq[Order](world.orders.len)
  for i, order in world.orders:
    result.orders[i] = order

proc fingerprint*(world: World): uint64 {.measure.} =
  ## Hashes deterministic gameplay fields for replay verification.
  result = 1469598103934665603'u64
  template mix(value: uint64) =
    result = (result xor value) * 1099511628211'u64
  template mixFixed(value: Fixed) =
    mix(cast[uint32](int32(value)).uint64)
  mix(world.tick.uint64)
  mix(world.rng.state)
  mix(world.effectsRng.state)
  mix(world.bodyCursor.uint64)
  mix(world.effectCursor.uint64)
  mix(world.endWait.uint64)
  mix(cast[uint64](world.winner.int64))
  mix(world.revision.uint64)
  mix(world.activeShips.uint64)
  mix(world.captures.uint64)
  mix(world.impacts.uint64)
  for p in world.planets:
    mix(p.owner.uint64)
    mix(p.production.uint64)
    mix(p.morale.uint64)
    mix(cast[uint64](p.realMorale.int64))
    mix(cast[uint64](p.ships))
    mix(cast[uint64](p.realShips))
    mixFixed(p.x)
    mixFixed(p.y)
    mix(p.frame.uint64)
    mix(p.textureSeed.uint64)
    mix(p.textureKind.uint64)
    for owner in 0 .. world.setup.players:
      mix(p.incoming[owner].uint64)
    mix(p.neighbors.len.uint64)
    for index in p.neighbors:
      mix(index.uint64)
  for i, body in world.bodies:
    if body.active:
      mix(i.uint64)
      mix(body.kind.ord.uint64)
      mixFixed(body.x)
      mixFixed(body.y)
      mixFixed(body.previousX)
      mixFixed(body.previousY)
      mixFixed(body.targetX)
      mixFixed(body.targetY)
      mixFixed(body.radius)
      mixFixed(body.speed)
      mixFixed(body.heading)
      mix(body.weight.uint64)
      mix(cast[uint64](body.target.int64))
      mix(uint64(body.hit))
      if body.kind == ShipBody:
        mix(world.ships[i].owner.uint64)
        mix(world.ships[i].target.uint64)
  for i, effect in world.effects:
    if effect.active:
      mix(i.uint64)
      mixFixed(effect.x)
      mixFixed(effect.y)
      mixFixed(effect.vx)
      mixFixed(effect.vy)
      mix(cast[uint64](effect.frame.int64))

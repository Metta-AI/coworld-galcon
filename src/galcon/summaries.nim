import common

const CardSeconds* = 10.0

type
  ShipSample* = object
    ships*: array[MaxPlayers + 1, int64]
    maximum*: int64
  Summary* = ref object
    samples*: seq[ShipSample]
    eliminated*: array[MaxPlayers + 1, int32]
    lastTick*: int32 = -1
  Card* = object
    shown*, terminal*, manual*: bool
    until*: float64

proc newSummary*(maximumTicks: int32): Summary =
  ## Reserves bounded viewer history without adding data to the simulation.
  result = Summary(samples: newSeq[ShipSample](maximumTicks.int + 1))
  for tick in result.eliminated.mitems:
    tick = -1

proc observe*(summary: Summary, world: World) =
  ## Counts planet stocks and airborne ships once per new recorded tick.
  if world.tick <= summary.lastTick:
    return
  doAssert world.tick.int < summary.samples.len
  doAssert world.tick == summary.lastTick + 1
  var
    sample: ShipSample
    present: array[MaxPlayers + 1, bool]
  for planet in world.planets:
    if planet.owner > 0:
      sample.ships[planet.owner] += planet.shipCount.int64
      present[planet.owner] = true
  for i, body in world.bodies:
    if body.active and body.kind == ShipBody:
      let owner = world.ships[i].owner
      inc sample.ships[owner]
      present[owner] = true
  if world.tick > 0:
    sample.maximum = summary.samples[world.tick - 1].maximum
  for owner in 1 .. world.setup.players:
    if world.winner >= 0 and world.winner != owner:
      present[owner] = false
      sample.ships[owner] = 0
    if not present[owner] and summary.eliminated[owner] < 0:
      summary.eliminated[owner] = world.tick
    sample.maximum = max(sample.maximum, sample.ships[owner])
  summary.samples[world.tick] = sample
  summary.lastTick = world.tick

proc update*(card: var Card, terminal: bool, now: float64) =
  ## Shows each newly reached ending for ten monotonic wall-clock seconds.
  if terminal and not card.terminal:
    card.shown = true
    card.manual = false
    card.until = now + CardSeconds
  elif not terminal and card.terminal:
    card.shown = false
    card.manual = false
    card.until = 0
  elif terminal and not card.manual and now >= card.until:
    card.shown = false
  card.terminal = terminal

proc toggle*(card: var Card) =
  ## Opens or dismisses the score card independently of playback controls.
  card.shown = not card.shown
  card.manual = card.shown

proc holding*(card: Card, now: float64): bool =
  ## Keeps automatic looping at the ending until the real-time hold expires.
  card.terminal and now < card.until

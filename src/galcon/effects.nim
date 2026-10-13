import
  polyworld/rngs,
  common

const
  MaxParticles* = 1024
  EffectHistoryTicks* = 38'i32
  ParticleSalt = 0x5041525449434c45'u64

type
  Particle* = object
    active*: bool
    born*: int32
    x*, y*, vx*, vy*: Fixed
    frame*: int
  Effects* = ref object
    particles*: array[MaxParticles, Particle]
    seed*: int32

proc clear*(effects: Effects) =
  ## Drops only viewer particles when playback jumps to another time.
  for particle in effects.particles.mitems:
    particle.active = false

proc explode(
    effects: Effects, rng: var Rng, cursor: var int,
    tick: int32, x, y, radius: Fixed, count: int
) =
  ## Recreates Phil's bounded sparks without storing or aging gameplay state.
  for i in 0 ..< count:
    inc cursor
    let
      slot = cursor mod MaxParticles
      angle = fixed(rng.between(0, 359)) * FixedPi / 180
      speed = fixed(rng.between(0, 99)) / 100
      bound = max(1, (radius * 100).toInt)
      distance = fixed(rng.below(bound)) / 100
      vx = speed * cos(angle)
      vy = speed * sin(angle)
    effects.particles[slot] = Particle(
      active: true,
      born: tick + 1,
      x: x + distance * vx * cos(angle),
      y: y + distance * vy * sin(angle),
      vx: vx, vy: vy,
      frame: rng.between(-5, 4).int
    )

proc observe*(effects: Effects, arrival: Arrival) =
  ## Seeds each impact independently so a short replay seek recreates its art.
  var
    rng = initRng(effects.seed, ParticleSalt xor arrival.impacts.uint64)
    total = arrival.impacts.int64 * 16 + arrival.captures.int64 * 512 - 16
  if arrival.captured:
    total -= 512
  var cursor = (total mod MaxParticles).int
  effects.explode(
    rng, cursor, arrival.tick, arrival.x, arrival.y, FixedOne, 16
  )
  if arrival.captured:
    effects.explode(
      rng, cursor, arrival.tick,
      arrival.planetX, arrival.planetY, fixed(arrival.radius.int32), 512
    )

proc position*(particle: Particle, tick: int32): tuple[x, y: Fixed] =
  ## Evaluates fixed-point motion at draw time without per-tick updates.
  let age = fixed(clamp(tick - particle.born, 0, EffectHistoryTicks))
  (particle.x + particle.vx * age, particle.y + particle.vy * age)

proc frame*(particle: Particle, tick: int32): int =
  ## Returns the original fade frame or an invisible frame outside its life.
  if not particle.active or tick < particle.born:
    return 33
  particle.frame + (tick - particle.born).int

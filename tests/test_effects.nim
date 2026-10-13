import
  std/os,
  galcon/[common, worlds, effects, sessions, options, replays]

proc samePicture(a, b: Effects, tick: int32) =
  ## Compares visible particles while ignoring expired pool slots.
  for i in 0 ..< MaxParticles:
    let
      first = a.particles[i]
      second = b.particles[i]
      visible = first.frame(tick) < 33
    doAssert visible == (second.frame(tick) < 33)
    if visible:
      doAssert first.frame(tick) == second.frame(tick)
      doAssert first.position(tick) == second.position(tick)

proc testEffects*() =
  ## Proves that viewer effects are isolated and survive live and file seeks.
  echo "Particles have no simulation state and analytical motion stays fixed"
  doAssert not compiles(World().effects)
  doAssert not compiles(World().effectsRng)
  doAssert not compiles(World().effectCursor)
  let particle = Particle(
    active: true, born: 100, frame: -5,
    x: fixed(10), y: fixed(20), vx: FixedOne / 3, vy: -FixedOne / 7
  )
  var
    x = particle.x
    y = particle.y
  for age in 0 .. EffectHistoryTicks:
    doAssert particle.position(100 + age) == (x, y)
    x += particle.vx
    y += particle.vy

  echo "Showing explosions cannot alter gameplay hashes or bot decisions"
  let
    path = Root / "build" / "visual-effects.replay"
    options = parseOptions(@[
      "--headless", "--players", "5", "--seed", "8", "--ticks", "640",
      "--record", path
    ])
    plainOptions = parseOptions(@[
      "--headless", "--players", "5", "--seed", "8", "--ticks", "640"
    ])
    viewer = newSession(options)
    plain = newSession(plainOptions)
    visible = Effects(seed: options.setup.seed)
    reference = Effects(seed: options.setup.seed)
  viewer.historyMargin = EffectHistoryTicks
  viewer.observer = proc(arrival: Arrival) =
    ## Observes gameplay without touching the authoritative world or policies.
    visible.observe(arrival)
  for tick in 1 .. 640:
    viewer.step()
    plain.step()
    doAssert viewer.world.fingerprint() == plain.world.fingerprint()
    if tick == 615:
      reference.particles = visible.particles
  doAssert viewer.world.impacts > 0 and viewer.world.captures > 0
  for owner in 1 .. 5:
    doAssert viewer.brains[owner].decisions == plain.brains[owner].decisions
  visible.clear()
  viewer.seek(615)
  samePicture(reference, visible, 615)
  visible.clear()
  viewer.seek(640)
  doAssert not viewer.inHistory
  doAssert viewer.world.fingerprint() == plain.world.fingerprint()
  let playback = newSession(parseOptions(@["--headless", "--replay", path]))
  playback.historyMargin = EffectHistoryTicks
  playback.observer = proc(arrival: Arrival) =
    ## Rebuilds the short visual history independently of replay checkpoints.
    visible.observe(arrival)
  visible.clear()
  playback.seek(615)
  samePicture(reference, visible, 615)
  doAssert playback.world.fingerprint() == viewer.recording.hashes[614]
  removeFile(path)

import
  std/[os, math, tables, strutils, monotimes, times],
  silky, pixie, vmath, chroma, bumpy, opengl, slappy,
  polyworld/profiles as gameProfiles,
  common, controls, textures, options, sessions, transports

const
  Green = rgbx(85, 255, 85, 255)
  White = rgbx(255, 255, 255, 255)
  Gray = rgbx(170, 170, 170, 255)
  Shadow = rgbx(0, 0, 0, 255)
  TutorialTexts = [
    "you are the green player.\n" &
      "click and hold on your planet,\n" &
      "drag to a target, then release.\n\n" &
      "click planets to select a group.\n" &
      "double-click yours to select all.\n\n" &
      "number keys change attack size.",
    "try to take over the red enemy.\n\n" &
      "capture good neutral planets first.\n" &
      "big planets produce more ships.\n\n" &
      "reinforce your planets so the\n" &
      "enemy cannot take over.",
    "production depends on morale.\n\n" &
      "morale rises near friendly planets\n" &
      "and when receiving reinforcements.\n\n" &
      "attacks and nearby enemies lower it.\n\n" &
      "tab cycles ships, production, morale."
  ]
  HelpText = "click planets to select a group.\n" &
    "double-click yours to select all.\n" &
    "drag from any planet to a target.\n" &
    "drag empty space to select a box.\n" &
    "right-click clears the selection.\n\n" &
    "1-9: 10-90%, 0: 100% ships\n" &
    "tab: ships / production / morale\n" &
    "space or f10: pause\n" &
    "f2: profile, f3: music\n" &
    "alt-enter: fullscreen\n" &
    "escape: return to menu\n\n" &
    "have fun!"

type
  Screen = enum
    MenuScreen, HelpScreen, GameScreen, TutorialScreen, EndScreen
  View = ref object
    window: Window
    sk: Silky
    options: Options
    paints: Paints
    session: Session
    controls: Controls
    screen: Screen
    offset: Vec2
    selection: int
    difficulty: Difficulty
    tutorial, stat, boardRevision, frames: int
    transport: Transport
    presentation: Presentation
    lastTime: MonoTime
    music, launchSound, blastSound, captureSound: Sound
    musicSource, launchSource, blastSource, captureSource: Source
    musicEnabled: bool
    seenCaptures, seenImpacts: int

proc ownerColor(owner: int): ColorRGBX =
  ## Converts the original player palette at the rendering boundary.
  let c = Colors[owner]
  rgbx(c[0], c[1], c[2], 255)

proc line(view: View, a, b: Vec2, color: ColorRGBX, width = 1.0'f) =
  ## Draws a two-dimensional line through Silky's triangle batch.
  let
    delta = b - a
    magnitude = length(delta)
  if magnitude < 0.001:
    return
  let
    normal = vec2(-delta.y, delta.x) / magnitude * width / 2
    uv = view.sk.atlas.entries[WhiteTileKey]
    sample = vec2(uv.x.float32 + 8, uv.y.float32 + 8)
    colors = [color, color, color]
    uvs = [sample, sample, sample]
  view.sk.drawTriangle([a + normal, a - normal, b + normal], uvs, colors)
  view.sk.drawTriangle([a - normal, b - normal, b + normal], uvs, colors)

proc ring(view: View, center: Vec2, radius: float32, color: ColorRGBX) =
  ## Draws the original bright circular selection marker in logical pixels.
  var previous = center + vec2(radius, 0)
  for i in 1 .. 64:
    let
      angle = i.float32 * PI.float32 / 32
      next = center + vec2(math.cos(angle), math.sin(angle)) * radius
    view.line(previous, next, color, 2)
    previous = next

proc text(
    view: View, font, value: string, position: Vec2,
    color = White, centered = false, shadow = true
) =
  ## Draws transparent glyphs with an optional one-pixel glyph shadow.
  let
    at = view.offset + position
    width = if centered: Width.float32 else: float32.high
    alignment = if centered: CenterAlign else: LeftAlign
  if shadow:
    discard view.sk.drawText(
      font, value, at + vec2(1, 1), Shadow,
      maxWidth = width, hAlign = alignment, clip = false
    )
  discard view.sk.drawText(
    font, value, at, color,
    maxWidth = width, hAlign = alignment, clip = false
  )

proc centeredLines(view: View, title, body: string) =
  ## Places original-font pause and tutorial text over the game background.
  let
    lines = body.splitLines()
    top = (Height - (lines.len + 3) * 22).float32 / 2
  view.text("Hud", title, vec2(0, top), centered = true)
  for i, value in lines:
    view.text("Small", value, vec2(0, top + 50 + i.float32 * 22),
      centered = true)
  view.text("Small", "click or press enter to continue",
    vec2(0, Height - 35), Gray, centered = true)

proc playSource(source: Source) =
  ## Reuses one bounded audio source rather than allocating on each impact.
  if source != nil:
    source.stop()
    source.play()

proc initSounds(view: View) =
  ## Loads Phil Hassey's original soundtrack and three sound effects.
  if view.options.muted:
    return
  try:
    view.music = newSound(Assets / "galcon.ogg", forceMono = false)
    view.launchSound = newSound(Assets / "launch.wav")
    view.blastSound = newSound(Assets / "blast.wav")
    view.captureSound = newSound(Assets / "takeover.wav")
    view.musicSource = view.music.play()
    view.musicSource.looping = true
    view.musicSource.stop()
    view.launchSource = view.launchSound.play()
    view.blastSource = view.blastSound.play()
    view.captureSource = view.captureSound.play()
    view.launchSource.stop()
    view.blastSource.stop()
    view.captureSource.stop()
    view.musicEnabled = true
  except SlappyError as error:
    echo "Original audio unavailable: ", error.msg

proc updateBoard(view: View) {.measure.} =
  ## Replaces the existing atlas board only when planet ownership changes.
  if view.boardRevision == view.session.world.revision:
    return
  let
    image = view.paints.boardImage(view.session.world)
    entry = view.sk.atlas.entries["Board"]
  view.sk.image.draw(image, translate(vec2(entry.x.float32, entry.y.float32)),
    OverwriteBlend)
  view.sk.uploadAtlas()
  view.boardRevision = view.session.world.revision

proc start(view: View, tutorial = 0) =
  ## Starts a seeded match or one of the original three tutorial maps.
  if view.session != nil:
    view.session.finish()
  var options = view.options.clone()
  options.setup =
    if tutorial > 0: tutorialSetup(options.game.seed, tutorial)
    else: options.matchSetup(view.difficulty)
  view.session = newSession(options)
  view.controls = Controls(player: view.session.human, percent: 50, anchor: -1,
    hover: -1)
  view.paints = newPaints(view.session.world.planets.len)
  view.boardRevision = -1
  view.updateBoard()
  view.screen = if tutorial > 0: TutorialScreen else: GameScreen
  view.tutorial = tutorial
  view.transport = Transport(player: initPlayer(
    not view.session.playback,
    view.session.maximumTicks,
    not options.game.pauseOnStart,
    options.game.speed
  ))
  view.lastTime = getMonoTime()
  view.seenCaptures = 0
  view.seenImpacts = 0
  if view.musicSource != nil and view.musicEnabled:
    view.musicSource.play()

proc menuAction(view: View) =
  ## Activates the selected item in the original four-item menu.
  case view.selection
  of 0: view.start(1)
  of 1: view.start()
  of 2: view.screen = HelpScreen
  of 3: view.window.closeRequested = true
  else: discard

proc returnToMenu(view: View) =
  ## Saves an interrupted local recording and restores the original menu.
  view.session.finish()
  view.screen = MenuScreen
  if view.musicSource != nil:
    view.musicSource.stop()

proc drawMenu(view: View) =
  ## Reproduces the original title, menu arrangement, and author credit.
  view.sk.drawImage("Background", view.offset)
  view.text("Title", "galcon 2006", vec2(0, 8), Green, centered = true)
  let items = ["tutorial", "play < " & ($view.difficulty).toLowerAscii() &
    " >", "help", "quit"]
  for i, item in items:
    view.text("Menu", item, vec2(0, 142 + i.float32 * 48),
      if i == view.selection: White else: Gray, centered = true)
  view.text("Hud", "use left/right to change level", vec2(0, 416), Gray,
    centered = true)
  view.text("Hud", "ludum dare #8 - phil hassey", vec2(0, 440), Gray,
    centered = true)

proc drawShips(view: View) =
  ## Draws the original hollow triangular ships with fixed simulation headings.
  let world = view.session.world
  for i, body in world.bodies:
    if not body.active or body.kind != ShipBody:
      continue
    let
      heading = math.arctan2(
        (body.y - body.previousY).toFloat32,
        (body.x - body.previousX).toFloat32
      )
      center = view.offset + vec2(body.x.toFloat32, body.y.toFloat32)
      color = ownerColor(world.ships[i].owner)
      a = center + vec2(math.cos(heading), math.sin(heading)) * 6
      back = center - vec2(math.cos(heading), math.sin(heading)) * 3
      side = vec2(-math.sin(heading), math.cos(heading)) * 3
      b = back + side
      c = back - side
    view.line(a, b, color)
    view.line(b, c, color)
    view.line(c, a, color)
  let particle = view.sk.atlas.entries["Particle"]
  for effect in world.effects:
    if not effect.active:
      continue
    let alpha =
      if effect.frame > 25: clamp(255 - (effect.frame - 25) * 31, 0, 255).uint8
      else: 255'u8
    view.sk.drawImage("Particle", view.offset + vec2(
      effect.x.toFloat32 - particle.width.float32 / 2,
      effect.y.toFloat32 - particle.height.float32 / 2
    ), rgbx(alpha, alpha, alpha, alpha))

proc drawGame(view: View) {.measure.} =
  ## Paints 2D art, translucent effects, transparent counts, and the LD8 HUD.
  view.updateBoard()
  view.sk.drawImage("Board", view.offset)
  view.drawShips()
  let world = view.session.world
  view.controls.clean(world)
  let selectionColor = ownerColor(max(view.session.human, 1))
  var
    selected = 0
    sending = 0
  for i, planet in world.planets:
    let center = view.offset + vec2(planet.x.toFloat32, planet.y.toFloat32)
    if view.controls.selected[i]:
      inc selected
      sending += roundedRatio(planet.ships * view.controls.percent,
        FixedScale * 100).int
      view.ring(center, planet.radius.float32 + 4, selectionColor)
      if view.controls.holding and not view.controls.box:
        let target =
          if view.controls.hover >= 0:
            let p = world.planets[view.controls.hover]
            view.offset + vec2(p.x.toFloat32, p.y.toFloat32)
          else:
            view.offset + vec2(view.controls.x.float32, view.controls.y.float32)
        view.line(center, target, selectionColor, 1.5'f)
    if view.stat != 3:
      let value =
        case view.stat
        of 1: planet.production
        of 2: planet.morale
        else: planet.shipCount
      let label = $value
      view.text("Numbers", label,
        vec2(planet.x.toFloat32 - label.len.float32 * 3.7'f,
          planet.y.toFloat32 - 8), White)
  if view.controls.holding and view.controls.box and view.controls.moved:
    let
      a = view.offset + vec2(min(view.controls.startX, view.controls.x).float32,
        min(view.controls.startY, view.controls.y).float32)
      b = view.offset + vec2(max(view.controls.startX, view.controls.x).float32,
        max(view.controls.startY, view.controls.y).float32)
    view.line(a, vec2(b.x, a.y), Green)
    view.line(vec2(b.x, a.y), b, Green)
    view.line(b, vec2(a.x, b.y), Green)
    view.line(vec2(a.x, b.y), a, Green)
  if view.controls.hover >= 0:
    let p = world.planets[view.controls.hover]
    view.text("Hud", "planet: " & p.name & "   production: " & $p.production &
      "   morale: " & $p.morale & "   ships: " & $p.shipCount,
      vec2(8, 4), Green)
  if view.session.human > 0 and not view.session.inHistory:
    let status =
      "From: " & $selected & " planets   Ships: " & $sending &
        " (" & $view.controls.percent & "%)"
    view.text("Hud", status, vec2(0, 450), selectionColor, centered = true)
  case view.screen
  of TutorialScreen:
    view.centeredLines("tutorial #" & $view.tutorial,
      TutorialTexts[view.tutorial - 1])
  of EndScreen:
    let title =
      if world.winner < 0: "time limit - draw"
      elif view.session.human == 0: "player " & $world.winner & " wins!"
      elif world.winner == view.session.human: "you win!"
      else: "you lose!"
    view.centeredLines(title, "")
  else:
    if not view.transport.player.playing and
      view.transport.player.targetTick < 0:
        view.text("Hud", "paused", vec2(0, 36), centered = true)

proc handleInput(view: View) =
  ## Normalizes native input into logical integer Galcon controls.
  let
    window = view.window
    game = view.screen in {GameScreen, TutorialScreen, EndScreen}
    pointer =
      if game:
        (window.mousePos.vec2 / view.sk.uiScale -
          view.presentation.boardOrigin) / view.presentation.boardScale
      else:
        window.mousePos.vec2 / view.sk.uiScale - view.offset
    x = floor(pointer.x).int
    y = floor(pointer.y).int
    onBoard = x in 0 ..< Width and y in 0 ..< Height
    clicked = window.buttonPressed[MouseLeft] and (not game or onBoard)
    entered = window.buttonPressed[KeyEnter]
    shift = window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]
  if entered and (window.buttonDown[KeyLeftAlt] or
    window.buttonDown[KeyRightAlt]):
      window.fullscreen = not window.fullscreen
      return
  if window.buttonPressed[KeyF2]:
    gameProfiles.toggleRuntimeTrace()
  if window.buttonPressed[KeyF3] and view.musicSource != nil:
    view.musicEnabled = not view.musicEnabled
    if view.musicEnabled and view.screen in {GameScreen, TutorialScreen}:
      view.musicSource.play()
    else:
      view.musicSource.stop()
  if game:
    if window.buttonPressed[KeySpace] or window.buttonPressed[KeyF10]:
      view.transport.player.togglePlay()
      view.controls.holding = false
  case view.screen
  of MenuScreen:
    if window.buttonPressed[KeyEscape]:
      window.closeRequested = true
    if window.buttonPressed[KeyDown]:
      view.selection = (view.selection + 1) mod 4
    if window.buttonPressed[KeyUp]:
      view.selection = (view.selection + 3) mod 4
    if window.buttonPressed[KeyRight]:
      view.difficulty = Difficulty((view.difficulty.ord + 1) mod 4)
    if window.buttonPressed[KeyLeft]:
      view.difficulty = Difficulty((view.difficulty.ord + 3) mod 4)
    let overMenu = x in 80 .. 560 and y in 142 .. 334
    if overMenu and window.mouseDelta != ivec2(0, 0):
      view.selection = clamp((y - 142) div 48, 0, 3)
    if entered or (clicked and overMenu):
      view.menuAction()
  of HelpScreen:
    if clicked or entered or window.buttonPressed[KeyEscape]:
      view.screen = MenuScreen
  of TutorialScreen:
    if clicked or entered:
      view.screen = GameScreen
    if window.buttonPressed[KeyEscape]:
      view.returnToMenu()
  of EndScreen:
    if clicked or entered:
      if view.tutorial in 1 .. 2 and view.session.world.winner == 1:
        view.start(view.tutorial + 1)
      else:
        view.returnToMenu()
    if window.buttonPressed[KeyEscape]:
      view.returnToMenu()
  of GameScreen:
    if window.buttonPressed[KeyEscape]:
      view.returnToMenu()
      return
    if window.buttonPressed[KeyTab]:
      view.stat = (view.stat + 1) mod 4
    let keys = [Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9]
    for i, key in keys:
      if window.buttonPressed[key]:
        view.controls.percent = if i == 0: 100 else: i * 10
    view.controls.point(view.session.world, x, y)
    if view.session.canCommand and view.transport.player.playing and
      view.transport.player.targetTick < 0:
      if window.buttonPressed[MouseRight]:
        view.controls.clear()
      if clicked or (window.buttonPressed[DoubleClick] and onBoard):
        view.controls.press(view.session.world, x, y,
          window.buttonPressed[DoubleClick], shift)
      if window.buttonReleased[MouseLeft]:
        if view.controls.release(view.session.world, x, y) > 0:
          view.launchSource.playSource()

proc capture(view: View) =
  ## Saves an actual Silky back-buffer screenshot for visual verification.
  let image = newImage(view.window.size.x, view.window.size.y)
  glReadPixels(0, 0, image.width.GLsizei, image.height.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
  image.flipVertical()
  image.writeFile(view.options.screenshot)
  view.window.closeRequested = true

proc layout(view: View) =
  ## Separates board scaling from the shared transport's logical coordinates.
  if view.screen in {GameScreen, TutorialScreen, EndScreen}:
    view.presentation = presentation(view.window.size.vec2)
    view.sk.uiScale = view.presentation.uiScale
    view.offset = vec2(0)
  else:
    view.sk.uiScale = min(view.window.size.x.float32 / Width,
      view.window.size.y.float32 / Height)
    let logicalSize = view.window.size.vec2 / view.sk.uiScale
    view.offset = (logicalSize - vec2(Width, Height)) / 2

proc frame(view: View) =
  ## Advances deterministic ticks through Polyworld's bounded transport loop.
  let
    now = getMonoTime()
    elapsed = min(0.25, (now - view.lastTime).inNanoseconds.float64 / 1e9)
    frameStart = epochTime()
  view.lastTime = now
  view.layout()
  view.handleInput()
  view.layout()
  if view.screen in {GameScreen, EndScreen}:
    if view.transport.advancePlayback(
      view.session,
      elapsed.float32,
      frameStart,
      singleTick = view.options.screenshot.len > 0
    ):
      view.controls.holding = false
      view.boardRevision = -1
    let world = view.session.world
    if not view.session.inHistory:
      if world.captures > view.seenCaptures:
        view.captureSource.playSource()
      elif world.impacts > view.seenImpacts:
        view.blastSource.playSource()
    view.seenCaptures = world.captures
    view.seenImpacts = world.impacts
    view.screen =
      if world.winner >= 0 or world.tick >= view.session.maximumTicks:
        EndScreen
      else:
        GameScreen
  view.sk.beginUi(view.window, view.window.size)
  view.sk.clearScreen(rgbx(0, 0, 0, 255))
  view.sk.pushClipRect(rect(view.offset, vec2(Width, Height)))
  case view.screen
  of MenuScreen: view.drawMenu()
  of HelpScreen:
    view.sk.drawImage("Background", view.offset)
    view.centeredLines("help", HelpText)
  else: view.drawGame()
  view.sk.popClipRect()
  if view.screen in {GameScreen, TutorialScreen, EndScreen}:
    for vertex in view.sk.drawer.layers[NormalLayer].mitems:
      vertex.pos = view.presentation.boardOrigin +
        vertex.pos * view.presentation.boardScale
      vertex.clipPos = view.presentation.boardOrigin +
        vertex.clipPos * view.presentation.boardScale
      vertex.clipSize *= view.presentation.boardScale
    view.transport.sync(view.session)
    let serial = view.transport.player.seekSerial
    view.transport.drawTransport(
      view.sk, view.window, view.presentation.panel
    )
    if serial != view.transport.player.seekSerial:
      view.controls.holding = false
  view.sk.endUi()
  inc view.frames
  if view.options.screenshot.len > 0 and view.frames >= view.options.frames:
    view.capture()
  view.window.swapBuffers()

proc runGraphics*(options: Options) =
  ## Opens a local Silky 2D window with the original assets and BASIC opponents.
  let
    size =
      if options.game.windowWidth > 0:
        ivec2(options.game.windowWidth, options.game.windowHeight)
      else: ivec2(960, 720)
    window = newWindow("Galcon 2006", size,
      vsync = options.game.vsync)
  window.makeContextCurrent()
  loadExtensions()
  let
    builder = newAtlasBuilder(2048, 2)
    paints = newPaints(MaxPlanets)
  doAssert builder.addImage("Background", paints.background)
  doAssert builder.addImage("Board", paints.background.copy())
  doAssert builder.addImage("Particle", paints.particle)
  builder.addFont(Assets / "SAVEDBYZ.TTF", "Title", 80)
  builder.addFont(Assets / "zeroes_3.ttf", "Menu", 48)
  builder.addFont(Assets / "zeroes_3.ttf", "Hud", 24)
  builder.addFont(Assets / "zeroes_3.ttf", "Small", 20)
  builder.addFont(Assets / "zeroes_3.ttf", "Numbers", 14)
  builder.addTransportAssets()
  let particle = builder.atlas.entries["Particle"]
  for y in 0 ..< paints.particle.height:
    for x in 0 ..< paints.particle.width:
      let pixel = paints.particle[x, y]
      # Zero coverage with emissive RGB gives the original additive sparks.
      builder.atlasImage[particle.x + x, particle.y + y] =
        rgbx(pixel.r, pixel.g, pixel.b, 0)
  let view = View(
    window: window,
    sk: newSilky(window, builder.atlasImage, builder.atlas),
    paints: paints,
    options: options,
    difficulty: options.setup.difficulty,
    screen: MenuScreen,
    selection: 1,
    lastTime: getMonoTime()
  )
  view.initSounds()
  if options.start:
    view.start(options.setup.tutorial)
  window.onFrame = proc() =
    ## Presents one interactive game frame.
    view.frame()
  while not window.closeRequested:
    pollEvents()
  if view.session != nil:
    view.session.finish()
  for source in [view.musicSource, view.launchSource, view.blastSource,
    view.captureSource]:
      if source != nil:
        source.stop()
  window.close()

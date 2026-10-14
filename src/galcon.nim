import
  galcon/[common, options, sessions]

when not defined(headless):
  import galcon/graphics

when defined(coworld):
  import std/[os, uri, strutils]
  import jsony
  import polyworld/[cli, coworld]
  import galcon/replays

  type HostedMap = ref object
    planets: int = 26
    difficulty: string = "easy"
    enemy_ships_pass_through: bool = true
    neutrals_dont_produce: bool = true

proc main*() =
  ## Starts the local Galcon port or a Polyworld Coworld policy match.
  var options = commandOptions()
  when defined(coworld):
    when compiles(coworldOptions(0, MaxTicks)):
      options.game = coworldOptions(0, MaxTicks)
    else:
      options.game = coworldOptions(0)
    if options.game.maximumTicks <= 0 or options.game.maximumTicks > MaxTicks:
      raise newException(GalconError, "Coworld duration exceeds Galcon limits")
    options.playerCount = options.game.botGroups.botCount()
    let map = readFile(parseUri(getEnv("COGAME_CONFIG_URI")).path.decodeUrl())
      .fromJson(HostedMap)
    options.planetCount = map.planets
    options.enemyShipsPassThrough = map.enemy_ships_pass_through
    options.neutralsDontProduce = map.neutrals_dont_produce
    case map.difficulty.toLowerAscii()
    of "easy": options.setup.difficulty = Easy
    of "medium": options.setup.difficulty = Medium
    of "hard": options.setup.difficulty = Hard
    of "crazy": options.setup.difficulty = Crazy
    else:
      raise newException(GalconError, "Invalid hosted difficulty")
    options.headless = true
    options.start = true
    options.resolveOptions()
  if options.headless:
    runHeadless(options)
  else:
    when not defined(headless):
      runGraphics(options)
    else:
      raise newException(GalconError, "This binary was built without graphics")

try:
  main()
except GalconError as error:
  quit("Galcon: " & error.msg, 1)

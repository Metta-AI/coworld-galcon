import
  galcon/[common, options, sessions]

when not defined(headless):
  import galcon/graphics

when defined(coworld):
  import polyworld/[cli, coworld]
  import galcon/replays

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

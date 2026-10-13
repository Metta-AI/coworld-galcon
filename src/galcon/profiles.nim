const
  ProfileTracePath* {.strdefine.} = ""
  ProfileFrames* {.intdefine.} = 512
  ProfileStartTick* {.intdefine.} = 2048

when ProfileTracePath.len > 0 or
  (not defined(headless) and not defined(emscripten)):
  import fluffy/measure
  when ProfileTracePath.len > 0:
    import std/os

  export measure

  var
    profileStarted = false
    profileDumped = false

  proc startProfileTrace*() =
    ## Starts one bounded Fluffy capture after simulation warmup.
    when ProfileTracePath.len > 0:
      if profileStarted or profileDumped:
        return
      let directory = ProfileTracePath.parentDir()
      if directory.len > 0:
        createDir(directory)
      profileStarted = true
      startTrace()

  proc finishProfileTrace*() =
    ## Writes the capture once without stopping the deterministic match.
    if not profileStarted or profileDumped:
      return
    profileDumped = true
    endTrace()
    dumpMeasures(ProfileTracePath)

  proc noteProfileTick*(tick: int32) =
    ## Captures a fixed tick interval with Fluffy's 10,000-event limit.
    when ProfileTracePath.len > 0:
      if tick == ProfileStartTick:
        startProfileTrace()
      if ProfileFrames > 0 and tick >= ProfileStartTick + ProfileFrames:
        finishProfileTrace()

  template profileBlock*(name: string, body: untyped) =
    ## Measures a named phase while a static or F2 capture is enabled.
    measurePush(name)
    try:
      body
    finally:
      measurePop()
else:
  macro measure*(fn: untyped): untyped =
    ## Removes procedure instrumentation from ordinary headless builds.
    fn

  proc finishProfileTrace*() =
    ## Leaves profiling disabled in an ordinary headless build.
    discard

  proc noteProfileTick*(tick: int32) =
    ## Leaves the normal deterministic tick pipeline unchanged.
    discard

  template profileBlock*(name: string, body: untyped) =
    ## Runs one phase without trace overhead in an ordinary headless build.
    body

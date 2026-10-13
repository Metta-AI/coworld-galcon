import
  std/[monotimes, times],
  galcon/[common, options, sessions, worlds]

const
  WarmupTicks* {.intdefine.} = 2048
  MeasuredTicks* {.intdefine.} = 512

proc benchmark*() =
  ## Measures the warmed five-bot match independently of trace allocations.
  let
    options = parseOptions(@[
      "--headless", "--players", "5", "--planets", "26", "--seed", "8",
      "--bot", Baseline & ":5", "--minutes", "10"
    ])
    session = newSession(options)
  for i in 0 ..< WarmupTicks:
    session.step()
  when defined(nimTypeNames):
    let before = getMemCounters()
  let started = getMonoTime()
  for i in 0 ..< MeasuredTicks:
    session.step()
  let elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1e9
  when defined(nimTypeNames):
    let after = getMemCounters()
    echo "allocations=", after[0] - before[0],
      " deallocations=", after[1] - before[1]
  echo "ticks=", MeasuredTicks, " seconds=", elapsed,
    " ticksPerSecond=", MeasuredTicks.float64 / elapsed,
    " hash=", session.world.fingerprint()

benchmark()

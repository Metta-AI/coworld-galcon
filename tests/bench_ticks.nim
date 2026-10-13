import
  benchy,
  galcon/[common, worlds, bots]

var checksum: uint64

timeIt "26-planet fixed map generation":
  let world = newWorld(defaultSetup())
  checksum = checksum xor world.fingerprint()

timeIt "32 fixed ticks with BASIC policies":
  let
    world = newWorld(defaultSetup())
    first = newBrain(world, 1, BaselineSource)
    second = newBrain(world, 2, BaselineSource)
  for i in 0 ..< TickRate:
    second.decide()
    first.decide()
    world.advance()
  checksum = checksum xor world.fingerprint()

echo "Checksum: ", checksum

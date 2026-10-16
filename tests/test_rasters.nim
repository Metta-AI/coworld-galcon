import
  std/os,
  pixie, silky, vmath,
  galcon/[common, rasters, textures, worlds]

proc testRasters*() =
  ## Verifies HD texture sizes, opaque planets, and logical font metrics.
  echo "HD assets and fonts retain logical sizes at fourfold pixel density"
  let
    original = newAtlasBuilder(512, 2)
    sharp = newAtlasBuilder(1024, 2)
    path = Assets / "zeroes_3.ttf"
  original.addFont(path, "Test", 14)
  sharp.addRasterFont(path, "Test", 14)
  let
    oldText = Silky(atlas: original.atlas)
    hdText = Silky(atlas: sharp.atlas)
    expected = oldText.getTextSize("Test", "Red (Andre Bot) 123")
    actual = hdText.rasterTextSize("Test", "Red (Andre Bot) 123")
  doAssert abs(expected.x - actual.x) < 0.01'f
  doAssert abs(expected.y - actual.y) < 0.01'f
  doAssert sharp.atlas.fonts["Test"].size == 14 * ArtScale
  let
    world = newWorld(configuredSetup(42, Easy, 16, 69))
    paints = newPaints(world.planets.len)
    planet = world.planets[0]
    before = world.fingerprint()
    surface = paints.planetImage(planet, 1)
    sprite = paints.planetSprite(planet, 1)
  doAssert paints.background.width == Width * ArtScale
  doAssert paints.background.height == Height * ArtScale
  doAssert paints.terrain.width == TextureSize * ArtScale
  doAssert paints.atmosphere.width == 324 * ArtScale
  doAssert surface.width == (planet.radius * 2 + 1) * ArtScale
  doAssert sprite.width == PlanetSpriteSize
  doAssert sprite.height == PlanetSpriteSize
  doAssert sprite[PlanetSpriteSize div 2, PlanetSpriteSize div 2].a == 255
  doAssert sprite[0, 0].a == 0
  doAssert world.fingerprint() == before

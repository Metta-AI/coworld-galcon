import std/[os, strutils]

switch("path", "src")
let dependencyRoot = getEnv("GALCON_DEPS")
if dependencyRoot.len > 0:
  for line in readFile(thisDir() / "galcon.lock").splitLines():
    let fields = line.splitWhitespace()
    if fields.len > 0:
      let directory = dependencyRoot / fields[0]
      switch("path",
        if dirExists(directory / "src"): directory / "src" else: directory)
else:
  switch("path", "../polyworld/src")
switch("define", "flatty64")
when not defined(emscripten):
  switch("define", "bassyNative")
when defined(coworld):
  switch("define", "headless")
  switch("threads", "on")
switch("nimcache", "build/nimcache")
when defined(emscripten):
  include "web.nims"

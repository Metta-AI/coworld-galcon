switch("path", "src")
switch("path", "../polyworld/src")
switch("define", "flatty64")
switch("define", "bassyNative")
when defined(coworld):
  switch("define", "headless")
  switch("threads", "on")
switch("nimcache", "build/nimcache")

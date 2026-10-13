' Announces its color and receives global messages using Polyworld mailboxes.
message$ = pullMailbox$()
while message$ <> ""
  message$ = pullMailbox$()
wend
if announced = 0 then
  announced = 1
  chatted = sendChat(-2, "Ready to conquer the galaxy.")
end if
if worldTick() > 0 and worldTick() mod 320 = 0 then
  chatted = sendChat(-2, "Still fighting. Watch your planets!")
end if
' Phil Hassey's original Galcon 2006 computer strategy, ported to BASIC.
' It shuffles each ready planet's neighbors every half second.
source = 0
while source < planetCount()
  if owner(source) = selfPlayer() and ready(source) <> 0 then
    shuffled = shuffleNeighbors(source)
    rank = 0
    while rank < neighborCount(source) and ships(source) >= 10 and realMorale(source) >= 25
      target = neighbor(source, rank)
      if owner(target) = selfPlayer() then
        if realMorale(source) - realMorale(target) > 10 then
          sent = launch(source, target, fraction(source, 1, 4))
        else
          if stronger(source, target) <> 0 then
            sent = launch(source, target, reinforcement(source, target))
          end if
        end if
      else
        sent = launch(source, target, fraction(source, 3, 4))
      end if
      rank = rank + 1
    wend
  end if
  source = source + 1
wend

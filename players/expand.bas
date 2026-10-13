' A second BASIC policy favors productive weak planets before enemy homes.
source = 0
while source < planetCount()
  if owner(source) = selfPlayer() and ready(source) <> 0 then
    if ships(source) >= 20 and realMorale(source) >= 25 then
      best = -1
      bestValue = -2147483647
      rank = 0
      while rank < neighborCount(source)
        target = neighbor(source, rank)
        if owner(target) <> selfPlayer() then
          value = production(target) * 3 - ships(target) * 2
          if value > bestValue then
            best = target
            bestValue = value
          end if
        end if
        rank = rank + 1
      wend
      if best >= 0 then
        sent = send(source, best, 75)
      end if
    end if
  end if
  source = source + 1
wend

--[[ Seekwell.Waypoint — Blizzard user waypoint + super track, TomTom when present, else coordinates in chat. ]]

Seekwell = Seekwell or {}
local W = {}
Seekwell.Waypoint = W

--- Returns "blizzard", "tomtom", "both" or "print".
function W.Set(mapID, x, y, label)
  mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
  if not (mapID and x and y) then
    return nil
  end
  local blizz, tom = false, false
  if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if Seekwell.Secret.Get(C_Map.CanSetUserWaypointOnMap, mapID) then
      blizz = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
      end)
      if blizz and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
    end
  end
  local tt = rawget(_G, "TomTom")
  if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
    tom = pcall(tt.AddWaypoint, tt, mapID, x, y, { title = label or "Seekwell", from = "Seekwell" })
  end
  local where = string.format("%.1f, %.1f", x * 100, y * 100)
  if blizz or tom then
    Seekwell.Print(string.format("waypoint: %s (%s)", tostring(label or "?"), where))
    return (blizz and tom) and "both" or (blizz and "blizzard" or "tomtom")
  end
  Seekwell.Print(string.format("%s: %s (map %d)", tostring(label or "?"), where, mapID))
  return "print"
end

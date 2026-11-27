--[[
  Seekwell extension points. Loaded early (before the feature modules) so that modules can register at file load;
  Core.lua (loaded last) consumes the tables.
    Seekwell.RegisterSlash("map", function(rest) ... end)        -> /sw map <rest>
    Seekwell.RegisterStart("map", function() ... end)            -> called once at login (pcall-guarded)
    Seekwell.RegisterStatus("map", function() return "text" end) -> a line in /sw status
]]

Seekwell = Seekwell or {}

Seekwell._slash = Seekwell._slash or {}
Seekwell._starters = Seekwell._starters or {}
Seekwell._status = Seekwell._status or {}

function Seekwell.RegisterSlash(cmd, fn)
  Seekwell._slash[cmd] = fn
end

function Seekwell.RegisterStart(name, fn)
  Seekwell._starters[#Seekwell._starters + 1] = { name = name, fn = fn }
end

function Seekwell.RegisterStatus(name, fn)
  Seekwell._status[#Seekwell._status + 1] = { name = name, fn = fn }
end

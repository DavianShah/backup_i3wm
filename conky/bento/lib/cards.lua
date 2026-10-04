--==============================================================================
--  BENTO CARDS — Cairo panels, rings, disk bars, power trace for Conky 1.10+
--  lua_load -> lua_draw_hook_pre = 'draw_bento_cards'  (drawn behind the text)
--
--  GEOMETRY
--    This file works in VIRTUAL conky units (the units used in ~/.conkyrc).
--    Xft.dpi=144 against a 96 dpi X server makes Conky multiply everything by
--    1.5, so physical pixels = VT * 1.5. The whole canvas is drawn with a
--    global cairo_scale(VT,VT), which keeps arcs and rounded corners crisp
--    because those are device-independent with Cairo.
--
--    virtual canvas 360 x 636   ->  physical 540 x 954
--    left text margin 20, ring centres 20 / 68 / 116 / 163, right edge 340
--
--  PANELS (virtual)
--    A  SSID row              y   0 ..  66
--    B  network               y  66 .. 152
--    C  system                y 152 .. 260
--    D1 storage  x 0  .. 112  y 260 .. 468
--    D2 media    x 120.. 360  y 260 .. 468
--    E  power trace           y 468 .. 636
--==============================================================================

require 'cairo'

local TAU  = 6.283185307179586
local VT   = 1.5                    -- conky virtual unit -> physical pixel
local FONT = 'JetBrainsMono Nerd Font Mono'

---------------------------------------------------------------------- utils ---

local function rounded(cr, x, y, w, h, r)
  if w < 2 * r then r = w / 2 end
  if h < 2 * r then r = h / 2 end
  cairo_new_sub_path(cr)
  cairo_arc(cr, x + w - r, y + r,     r, -math.pi / 2, 0)
  cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
  cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2, math.pi)
  cairo_arc(cr, x + r,     y + r,     r, math.pi, -math.pi / 2)
  cairo_close_path(cr)
end

local function panel(cr, x, y, w, h, r, alpha)
  cairo_set_source_rgba(cr, 0, 0, 0, alpha)
  rounded(cr, x, y, w, h, r)
  cairo_fill(cr)

  cairo_set_line_width(cr, 1)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.09)
  rounded(cr, x + 0.35, y + 0.35, w - 0.7, h - 0.7, r)
  cairo_stroke(cr)
end

-- Circular gauge swept clockwise from 12 o'clock.
local function arc(cr, cx, cy, radius, lw, ratio, r, g, b, a)
  if ratio <= 0.003 then return end
  if ratio > 1 then ratio = 1 end
  cairo_set_line_width(cr, lw)
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
  cairo_set_source_rgba(cr, r, g, b, a)
  cairo_arc(cr, cx, cy, radius, -math.pi / 2, -math.pi / 2 + ratio * TAU)
  cairo_stroke(cr)
end

local function track(cr, cx, cy, radius, lw)
  cairo_set_line_width(cr, lw)
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  cairo_arc(cr, cx, cy, radius, 0, TAU)
  cairo_stroke(cr)
end

local function bar(cr, x, y, w, h, r, ratio, fr, fg, fb)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  rounded(cr, x, y, w, h, r)
  cairo_fill(cr)
  if ratio <= 0.004 then return end
  if ratio > 1 then ratio = 1 end
  local fw = w * ratio
  if fw < h then fw = h end
  cairo_set_source_rgba(cr, fr, fg, fb, 0.95)
  rounded(cr, x, y, fw, h, r)
  cairo_fill(cr)
end

local function num(field)
  return tonumber(conky_parse(field)) or 0
end

--------------------------------------------------------------------- panels ---

local function draw_panels(cr)
  panel(cr,   2,   2, 356,  62, 11, 0.38)   -- A  SSID
  panel(cr,   2,  66, 356,  86, 11, 0.38)   -- B  network
  panel(cr,   2, 152, 356, 110, 11, 0.38)   -- C  system
  panel(cr,   2, 260, 110, 208, 11, 0.38)   -- D1 storage
  panel(cr, 120, 260, 238, 208, 11, 0.38)   -- D2 media
  panel(cr,   2, 468, 356, 166, 11, 0.38)   -- E  power trace
end

local function draw_network(cr)
  -- green download ring beside Dn, grey upload ring beside Up
  arc(cr,   20, 100, 11, 4, num('${downspeedf wlan0}') / 1250, 0.196, 0.843, 0.298, 0.95)
  track(cr, 20, 120, 11, 4)
  arc(cr,   20, 120, 11, 4, num('${upspeedf wlan0}') / 200, 1, 1, 1, 0.55)
end

local function draw_system(cr)
  -- four icon gauges: CPU, root disk, battery, package temperature
  local vals = {
    num('${cpu cpu0}'),
    num('${fs_used_perc /}'),
    num('${battery_percent BAT0}'),
    num('${execi 10 sensors | awk \'/Tctl/ {gsub("\\\\+|°C","",$2); print $2}\'}'),
  }
  local xs = { 20, 68, 116, 163 }
  for i = 1, 4 do
    track(cr, xs[i], 196, 7.5, 3)
    arc(cr, xs[i], 196, 7.5, 3, (vals[i] or 0) / 100, 0.196, 0.843, 0.298, 0.95)
  end

  -- disk bars, captions live ABOVE the bars in ~/.conkyrc
  bar(cr, 20, 238, 150, 8, 4, num('${fs_used_perc /}')     / 100, 1.000, 0.271, 0.224)
  bar(cr, 20, 256, 150, 8, 4, num('${fs_used_perc /home}') / 100, 0.196, 0.843, 0.298)
end

-- Power trace ---------------------------------------------------------------
local G1 = { 0.207, 0.882, 0.207 }
local G2 = { 0.435, 0.972, 0.435 }
local G3 = { 0.690, 1.000, 0.690 }

local function draw_power(cr, cols)
  local X, Y, W, H = 20, 488, 320, 132
  local n = #cols

  cairo_set_line_width(cr, 1)
  cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
  for i = 0, 6 do
    local x = X + (W - 1) * i / 6
    cairo_move_to(cr, x, Y)
    cairo_line_to(cr, x, Y + H)
  end
  for i = 0, 3 do
    local y = Y + H * i / 3
    cairo_move_to(cr, X, y)
    cairo_line_to(cr, X + W - 1, y)
  end
  cairo_stroke(cr)

  local function v(i)
    local j = n - W + i
    if j < 1 then return 0 end
    return cols[j] or 0
  end

  cairo_set_line_width(cr, 2.6)
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
  cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
  for i = 1, W - 1 do
    local x0, x1 = X + i - 1, X + i
    local y0, y1 = Y + H - H * v(i), Y + H - H * v(i + 1)
    cairo_set_source_rgba(cr, G1[1], G1[2], G1[3], 0.85)
    cairo_move_to(cr, x0, y0); cairo_line_to(cr, x1, y1); cairo_stroke(cr)
    cairo_set_source_rgba(cr, G2[1], G2[2], G2[3], 0.90)
    cairo_move_to(cr, x0, y0 - 2); cairo_line_to(cr, x1, y1 - 2); cairo_stroke(cr)
    cairo_set_source_rgba(cr, G3[1], G3[2], G3[3], 0.95)
    cairo_move_to(cr, x0, y0 - 4); cairo_line_to(cr, x1, y1 - 4); cairo_stroke(cr)
  end
end

--------------------------------------------------------------- power source ---

local power_path = false

local function find_power()
  local dirs = ''
  local fh = io.popen('ls -1 /sys/class/hwmon 2>/dev/null')
  if fh then dirs = fh:read('*a') or ''; fh:close() end
  for dir in dirs:gmatch('[^%s]+') do
    local nf = io.open('/sys/class/hwmon/' .. dir .. '/name', 'r')
    if nf then
      local name = (nf:read('*l') or ''):gsub('%s+$', '')
      nf:close()
      local file
      if name == 'amdgpu' then file = 'power1_average'
      elseif name == 'k10temp' or name == 'BAT0' then file = 'power1_input' end
      if file then
        local p = '/sys/class/hwmon/' .. dir .. '/' .. file
        local f = io.open(p, 'r')
        if f then f:close(); return p end
      end
    end
  end
  return nil
end

------------------------------------------------------------------ the hook ---

local history   = {}
local last_tick = -1

function conky_draw_bento_cards()
  if conky_window == nil then return end

  -- conky_window.width can read 0 under double buffering; the config geometry
  -- is authoritative and matches the text grid exactly.
  local w = 360 * VT
  local h = 636 * VT

  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                       conky_window.visual, w, h)
  local cr = cairo_create(cs)
  cairo_scale(cr, VT, VT)

  cairo_set_source_rgb(cr, 0.043, 0.047, 0.059)    -- #0b0c0f opaque canvas
  cairo_paint(cr)

  draw_panels(cr)
  draw_network(cr)
  draw_system(cr)

  if power_path == false then power_path = find_power() end
  local tick = math.floor(os.time() / 2)
  if tick ~= last_tick then
    last_tick = tick
    local watts = 0
    if power_path then
      local f = io.open(power_path, 'r')
      if f then watts = (tonumber(f:read('*n')) or 0) / 1e6; f:close() end
    end
    table.insert(history, math.min(watts / 45, 1))
    while #history > 320 do table.remove(history, 1) end
  end

  draw_power(cr, history)

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

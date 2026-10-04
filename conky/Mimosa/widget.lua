-- B&W system widget for conky (cairo, flat-function API)
-- network card (top) -> storage|music row -> gauge rectangle (bottom)
package.cpath = '/home/davi/.local/conky/usr/lib/conky/lib?.so;' .. package.cpath
require 'cairo'

local FONT = 'JetBrainsMono Nerd Font'

-- palette (black & white only)
local WHITE  = {1.00, 1.00, 1.00, 1.00}
local GRAY   = {0.62, 0.62, 0.62, 1.00}
local DIM    = {0.42, 0.42, 0.42, 1.00}
local CARD   = {0.12, 0.12, 0.12, 1.00}
local EDGE   = {1, 1, 1, 0.10}
local TRACK  = {0.22, 0.22, 0.22, 1.00}

-- geometry
local NET   = {x = 0,   y = 0,   w = 264, h = 94}
local STOR  = {x = 0,   y = 104, w = 127, h = 108}
local MUSIC = {x = 137, y = 104, w = 127, h = 108}
local RECT  = {x = 0,   y = 222, w = 264, h = 100}

local EXT = nil -- shared text extents struct

-- conky value access -----------------------------------------------------
local function P(s)
  local ok, v = pcall(function() return conky_parse(s) end)
  if ok and v then
    v = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    if v ~= '' and v ~= 'No Address' then return v end
  end
  return nil
end

local function Pnum(s)
  local v = P(s)
  if v then
    local raw = v:gsub('[^%d%-%.%,]', ''):gsub(',', '.')
    return tonumber(raw:match('[-%d%.]+'))
  end
  return nil
end

local function fmtbytes(b)
  if not b then return '--' end
  b = math.floor(b)
  if b < 1024 then return string.format('%dB', b) end
  b = b / 1024
  if b < 1024 then return string.format('%.0fKiB', b) end
  b = b / 1024
  if b < 1024 then return string.format('%.1fMiB', b) end
  return string.format('%.2fGiB', b / 1024)
end

-- text helpers (flat cairo API) ------------------------------------------
local function measure(cr, s, size, bold)
  cairo_select_font_face(cr, FONT, 'normal', bold and 'bold' or 'normal')
  cairo_set_font_size(cr, size)
  cairo_text_extents(cr, s, EXT)
  return tonumber(EXT.width), tonumber(EXT.height),
         tonumber(EXT.x_bearing), tonumber(EXT.y_bearing)
end

local function setcol(cr, col)
  cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4])
end

local function ctext(cr, s, cx, cy, size, col, bold)
  local w, h, xb, yb = measure(cr, s, size, bold)
  setcol(cr, col)
  cairo_move_to(cr, cx - w / 2 - xb, cy - h / 2 - yb)
  cairo_show_text(cr, s)
end

local function ltext(cr, s, x, cy, size, col, bold)
  local _, h, _, yb = measure(cr, s, size, bold)
  setcol(cr, col)
  cairo_move_to(cr, x, cy - h / 2 - yb)
  cairo_show_text(cr, s)
end

local function truncate(cr, s, maxw, size, bold)
  if not s or s == '' then return '' end
  local w = measure(cr, s, size, bold)
  if w <= maxw then return s end
  while #s > 1 do
    s = s:sub(1, #s - 1)
    if measure(cr, s .. '..', size, bold) <= maxw then return s .. '..' end
  end
  return s
end

local function round_rect(cr, x, y, w, h, r)
  r = math.min(r, w / 2, h / 2)
  cairo_move_to(cr, x + r, y)
  cairo_line_to(cr, x + w - r, y)
  cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
  cairo_line_to(cr, x + w, y + h - r)
  cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
  cairo_line_to(cr, x + r, y + h)
  cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
  cairo_line_to(cr, x, y + r)
  cairo_arc(cr, x + r, y + r, r, math.pi, math.pi * 1.5)
  cairo_close_path(cr)
end

local function card(cr, c)
  round_rect(cr, c.x, c.y, c.w, c.h, 14)
  setcol(cr, CARD)
  cairo_fill_preserve(cr)
  setcol(cr, EDGE)
  cairo_set_line_width(cr, 1)
  cairo_stroke(cr)
end

local function hbar(cr, x, y, w, h, frac, fill)
  frac = math.max(0, math.min(1, frac or 0))
  round_rect(cr, x, y, w, h, h / 2)
  setcol(cr, TRACK)
  cairo_fill(cr)
  if frac > 0 then
    round_rect(cr, x, y, math.max(h, w * frac), h, h / 2)
    setcol(cr, fill)
    cairo_fill(cr)
  end
end

local function ring(cr, cx, cy, r, frac, lw)
  cairo_new_path(cr) -- kill stale current point, else cairo_arc draws a line from it
  frac = math.max(0, math.min(1, frac or 0))
  cairo_set_line_width(cr, lw)
  cairo_set_line_cap(cr, 1)
  setcol(cr, TRACK)
  cairo_arc(cr, cx, cy, r, 0, math.pi * 2)
  cairo_stroke(cr)
  if frac > 0 then
    setcol(cr, WHITE)
    cairo_arc(cr, cx, cy, r, -math.pi / 2, -math.pi / 2 + frac * math.pi * 2)
    cairo_stroke(cr)
  end
  cairo_set_line_cap(cr, 0)
end

-- network history (one sample per update, raw sysfs byte counters)
local hist = { dn = {}, up = {} }
local prev = { dn = nil, up = nil, t = nil }
local UPDATE = 5

local function net_bytes(field)
  local h = io.open('/sys/class/net/wlan0/statistics/' .. field, 'r')
  if not h then return nil end
  local v = tonumber(h:read('*l'))
  h:close()
  return v
end

local function push_sample()
  local d = net_bytes('rx_bytes')
  local u = net_bytes('tx_bytes')
  local now = os.time()
  local dt = prev.t and math.max(1, now - prev.t) or UPDATE
  local vdn, vup = 0, 0
  if d and prev.dn and d >= prev.dn then vdn = (d - prev.dn) / dt end
  if u and prev.up and u >= prev.up then vup = (u - prev.up) / dt end
  prev.dn, prev.up, prev.t = d, u, now
  table.insert(hist.dn, vdn)
  table.insert(hist.up, vup)
  while #hist.dn > 40 do table.remove(hist.dn, 1) end
  while #hist.up > 40 do table.remove(hist.up, 1) end
  return vdn, vup
end

local function sparkline(cr, h, x, y, w, hgt)
  local n = #h
  if n < 2 then return end
  local step = 3
  local cols = math.floor(w / step)
  local maxv = 64 * 1024
  local start = math.max(1, n - cols + 1)
  for i = start, n do
    if h[i] > maxv then maxv = h[i] end
  end
  setcol(cr, {WHITE[1], WHITE[2], WHITE[3], 0.92})
  local shown = n - start + 1
  for i = start, n do
    local v = h[i]
    local cx = x + (shown - (n - i)) * step
    if v > 0 then
      local ch = math.max(1, v / maxv * (hgt - 1))
      cairo_rectangle(cr, cx, y + hgt - ch, step - 1, ch)
      cairo_fill(cr)
    end
  end
  setcol(cr, DIM)
  cairo_rectangle(cr, x, y + hgt, w, 1)
  cairo_fill(cr)
end

local ICONS = {
  cpu  = utf8.char(0xF2DB),
  bat  = utf8.char(0xF240),
  temp = utf8.char(0xF2C9),
  ram  = utf8.char(0xEFC5), -- fa-memory (f538 missing from this Nerd Font build)
  wifi = utf8.char(0xF1EB),
  note = utf8.char(0xF001),
}

local function music_data()
  local line = P('${execi 10 /home/davi/.config/conky/Mimosa/music.sh}')
  if not line then return nil end
  local st, ar, ti, du = line:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)')
  if not st or st == '' or st == 'OFF' then return nil end
  return { status = st, artist = ar or '', title = ti or '', dur = du or '' }
end

-- main draw --------------------------------------------------------------
local function draw(cr)
  local vcpu  = math.min(Pnum('${cpu}') or 0, 100)
  local vstor = math.min(Pnum('${fs_used_perc /}') or 0, 100)
  local vbat  = Pnum('${battery_percent BAT0}')
  local vram   = Pnum('${memperc}') or 0
  local vtemp = Pnum('${acpitemp}')
  local fsu   = P('${fs_used /}')
  local fsf   = P('${fs_free /}')
  local bootp = Pnum('${fs_used_perc /boot/efi}')
  local bootu = P('${fs_used /boot/efi}')
  local conn  = P([[${execi 10 nmcli -t -f NAME,DEVICE connection show --active | grep ':wlan0$' | cut -d: -f1}]]) or 'wlan0'
  local vdn, vup = push_sample()
  local mus   = music_data()

  card(cr, NET)
  card(cr, STOR)
  card(cr, MUSIC)
  card(cr, RECT)

  -- network card ---------------------------------------------------------
  ltext(cr, ICONS.wifi, NET.x + 13, NET.y + 20, 11, WHITE)
  ltext(cr, truncate(cr, conn, 130, 10, true), NET.x + 31, NET.y + 20, 10, WHITE, true)

  ltext(cr, 'Dn:', NET.x + 13, NET.y + 46, 9, GRAY)
  ltext(cr, fmtbytes(vdn), NET.x + 37, NET.y + 46, 9, WHITE, true)
  ltext(cr, '>>', NET.x + 118, NET.y + 46, 9, DIM)
  sparkline(cr, hist.dn, NET.x + 150, NET.y + 34, 99, 18)

  ltext(cr, 'Up:', NET.x + 13, NET.y + 74, 9, GRAY)
  ltext(cr, fmtbytes(vup), NET.x + 37, NET.y + 74, 9, WHITE, true)
  ltext(cr, '>>', NET.x + 118, NET.y + 74, 9, DIM)
  sparkline(cr, hist.up, NET.x + 150, NET.y + 62, 99, 18)

  -- storage card ---------------------------------------------------------
  ltext(cr, 'Storage', STOR.x + 13, STOR.y + 20, 11, WHITE, true)
  ltext(cr, string.format('System: %d%% (%s)', vstor or 0, fsu or '--'),
        STOR.x + 13, STOR.y + 41, 8, GRAY)
  hbar(cr, STOR.x + 13, STOR.y + 50, 101, 6, (vstor or 0) / 100, WHITE)
  if bootp then
    ltext(cr, string.format('Boot: %d%% (%s)', bootp, bootu or '--'),
          STOR.x + 13, STOR.y + 70, 8, GRAY)
    hbar(cr, STOR.x + 13, STOR.y + 79, 101, 6, bootp / 100, WHITE)
    ltext(cr, string.format('Free %s', fsf or '--'), STOR.x + 13, STOR.y + 97, 8, DIM)
  else
    ltext(cr, string.format('Free %s', fsf or '--'), STOR.x + 13, STOR.y + 70, 8, DIM)
  end

  -- music card -----------------------------------------------------------
  local mcx = MUSIC.x + MUSIC.w / 2
  ctext(cr, ICONS.note, mcx, MUSIC.y + 26, 20, WHITE)
  if mus then
    ctext(cr, mus.status == 'Paused' and 'Paused' or 'Playing',
          mcx, MUSIC.y + 52, 8, GRAY)
    ctext(cr, truncate(cr, mus.artist, 101, 9, true), mcx, MUSIC.y + 68, 9, WHITE, true)
    ctext(cr, truncate(cr, mus.title, 101, 8), mcx, MUSIC.y + 83, 8, GRAY)
    if mus.dur ~= '' then
      ctext(cr, mus.dur, mcx, MUSIC.y + 97, 8, DIM)
    end
  else
    ctext(cr, 'Nothing playing', mcx, MUSIC.y + 58, 9, GRAY)
    ctext(cr, '--', mcx, MUSIC.y + 74, 8, DIM)
  end

  -- gauge rectangle ------------------------------------------------------
  local gauges = {
    { icon = ICONS.cpu,  lbl = 'CPU',   val = vcpu,  txt = string.format('%d%%', vcpu) },
    { icon = ICONS.ram,  lbl = 'RAM',  val = vram,  txt = string.format('%d%%', vram) },
    { icon = ICONS.bat,  lbl = 'Bat',   val = vbat,  txt = vbat and string.format('%d%%', vbat) or '--' },
    { icon = ICONS.temp, lbl = 'Temp',  val = vtemp, txt = vtemp and string.format('%d°C', vtemp) or '--' },
  }
  for i, g in ipairs(gauges) do
    local cx = RECT.x + (i - 0.5) * (RECT.w / 4)
    local cy = RECT.y + 40
    local frac = 0
    if g.val then frac = math.max(0, math.min(1, g.val / 100)) end
    ring(cr, cx, cy, 21, frac, 4)
    ctext(cr, g.icon, cx, cy, 13, WHITE)
    ctext(cr, g.lbl, cx, RECT.y + 72, 8, GRAY)
    ctext(cr, g.txt, cx, RECT.y + 90, 11, WHITE, true)
  end
end

function conky_widget_draw()
  if conky_window == nil then return end
  EXT = EXT or cairo_text_extents_t.create()
  local cs = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable, conky_window.visual,
    conky_window.width, conky_window.height)
  local cr = cairo_create(cs)
  cairo_scale(cr, 1.5, 1.5) -- design grid 264x322 -> 396x483 device px
  local ok, err = pcall(draw, cr)
  if not ok then print('widget error: ' .. tostring(err)) end
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

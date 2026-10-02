--[==[
	Version		: 1.4
	Author		: Closebox73
	Description	: Draw multi bar for storage status with rounded option
]==]

require 'cairo'

-- Helper function to draw rounded rectangles
function draw_rounded_rectangle(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi, -math.pi/2)
    cairo_close_path(cr)
end

-- Function to draw a disk usage bar with label
function draw_disk_bar(cr, label, value, total, x, y, w, h, r, bg_color, fg_color)
    -- Draw background bar
    cairo_set_source_rgba(cr, bg_color[1], bg_color[2], bg_color[3], bg_color[4])
    draw_rounded_rectangle(cr, x, y, w, h, r)
    cairo_fill(cr)

    -- Draw foreground fill based on usage
    local fill_width = (value / 100) * w
    cairo_set_source_rgba(cr, fg_color[1], fg_color[2], fg_color[3], fg_color[4])
    draw_rounded_rectangle(cr, x, y, fill_width, h, r)
    cairo_fill(cr)

    -- Draw label text
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_select_font_face(cr, "Abel", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, 11)
    cairo_move_to(cr, x, y - 8)
    cairo_show_text(cr, string.format("%s: %d%% (%s)", label, value, total))
end

-- Main function called by Conky
function conky_draw_disk_bars()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- Get usage values and total sizes
    local root = tonumber(conky_parse("${fs_used_perc /}")) or 0
    local root_size = conky_parse("${fs_size /}") or "?"

    local home = tonumber(conky_parse("${fs_used_perc /home}")) or 0
    local home_size = conky_parse("${fs_size /home}") or "?"

    -- Position and dimensions
    local x, y = 18, 500
    local width, height = 115, 16
    local radius = 8
    local spacing = 46

    -- Colors
    local bg = {1, 1, 1, 0.1}
    local fg_root = {1.0, 0.2705, 0.2235, 1.0}
    local fg_home = {0.1960, 0.8431, 0.2980, 1.0}

    -- Draw bars
    draw_disk_bar(cr, "System", root, root_size, x, y, width, height, radius, bg, fg_root)
    draw_disk_bar(cr, "Home", home, home_size, x, y + spacing, width, height, radius, bg, fg_home)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

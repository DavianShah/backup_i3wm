--[==[
	Version		: 1.3
	Author		: Closebox73
	Description	: system_rings.lua: 4 rings for CPU, RAM, Battery, and Temperature (acpitemp)
]==]

require 'cairo'

-- Ring configuration table
system_rings = {
    {
        name = 'cpu',
        arg = 'cpu0',
        max = 100,
        x = 49.5, y = 345.5,
        radius = 25,
        thickness = 7,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true
    },
    {
        name = 'memperc',
        arg = '',
        max = 100,
        x = 119.7, y = 345.5,
        radius = 25,
        thickness = 7,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xffffff,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true
    },
    {
        name = 'battery_percent',
        arg = 'BAT0',
        max = 100,
        x = 190, y = 345.5,
        radius = 25,
        thickness = 7,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true
    },
    {
        name = 'execi',
        arg = '10 sensors | awk \'/Core 0/ {gsub("\\\\+|°C",""); t1=$3} /Core 1/ {gsub("\\\\+|°C",""); t2=$3} END {print int((t1+t2)/2)}\'',
        max = 100,
        x = 259.5, y = 345.5,
        radius = 25,
        thickness = 7,
        start_angle = 0,
        end_angle = 360,
        bg_color = 0xFFFFFF,
        bg_alpha = 0.1,
        fg_color = 0x32d74c,
        fg_alpha = 1.0,
        rounded = true
    }
}

-- Converts hex color to normalized RGBA components
function rgb_to_r_g_b(colour, alpha)
	return ((colour / 0x10000) % 0x100) / 255.,
	       ((colour / 0x100) % 0x100) / 255.,
	       (colour % 0x100) / 255.,
	       alpha
end

-- Draws a single ring with background and foreground arcs
function draw_system_ring(cr, ring, value)
    local angle_0 = (ring.start_angle or 0) * math.pi/180 - math.pi/2
    local angle_f = (ring.end_angle or 360) * math.pi/180 - math.pi/2
    local angle_v = angle_0 + (angle_f - angle_0) * (value / ring.max)

    cairo_set_line_width(cr, ring.thickness)
    cairo_set_line_cap(cr, ring.rounded and CAIRO_LINE_CAP_ROUND or CAIRO_LINE_CAP_BUTT)

    -- Draw background arc
    cairo_arc(cr, ring.x, ring.y, ring.radius, angle_0, angle_f)
    cairo_set_source_rgba(cr, rgb_to_r_g_b(ring.bg_color, ring.bg_alpha))
    cairo_stroke(cr)

    -- Draw foreground arc representing the value
    cairo_arc(cr, ring.x, ring.y, ring.radius, angle_0, angle_v)
    cairo_set_source_rgba(cr, rgb_to_r_g_b(ring.fg_color, ring.fg_alpha))
    cairo_stroke(cr)
end

-- Main function called by Conky
function conky_system_rings()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- Loop through all rings and draw them
    for i, ring in ipairs(system_rings) do
        local val = tonumber(conky_parse('${' .. ring.name .. ' ' .. ring.arg .. '}')) or 0
        draw_system_ring(cr, ring, val)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

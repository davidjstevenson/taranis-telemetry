local BATT_FILE = "/SCRIPTS/TELEMETRY/batt.dat"

local FOOTER_Y = 53
local FOOTER_TEXT_OFFSET = 3

local mah = 1500
local cells = 3
local low = 10.5
local high = 12.6

local mode = ""
local armed = false

local batteries = {}
local batt_index = 1

function Battery(entry)
    batteries[#batteries + 1] = entry
end

local function save_batteries()
    local file = io.open(BATT_FILE, "w")
    for i=1,#batteries do
        local entry = string.format(
            "Battery {\n    mah = %d,\n    cells = %d,\n    low = %.1f,\n    high = %.1f\n}\n",
            batteries[i].mah, batteries[i].cells,
            batteries[i].low, batteries[i].high)
        io.write(file, entry)
    end
    io.close(file)
end

-- UTIL FUNCTIONS --

local function round(val, decimal)
    if (decimal) then
        return math.floor( (val * 10^decimal) + 0.5) / (10^decimal)
    else
        return math.floor(val+0.5)
    end
end

local function formatTime(s)
    return string.format("%.2d:%.2d:%.2d", s/(60*60), s/60%60, s%60)
end

-- Tmp1 : actual flight mode, sent as 4 digits. Number is sent as (1)1234. 
--        Please ignore the leading 1, it is just there to ensure the number
--        as always 5 digits (the 1 + 4 digits of actual data) the numbers
--        are aditives (for example, if first digit after the leading 1 is
--        6, it means GPS Home and Headfree are both active) :
-- 1: 1 is GPS Hold, 2 is GPS Home, 4 is Headfree
-- 2: 1 is mag enabled, 2 is baro enabled, 4 is sonar enabled
-- 3: 1 is angle, 2 is horizon, 4 is passthrough
-- 4: 1 is ok to arm, 2 is arming is prevented, 4 is armed
local function parseTmp1()
    local tmp1 = getValue("Tmp1")

    local arm = tmp1 - math.floor(tmp1 / 10) * 10
    local fm = math.floor((tmp1 - math.floor(tmp1 / 100) * 100)/10)

    armed = arm == 5

    if fm == 1 then mode = "ANGL"
    elseif fm == 2 then mode = "HRZN"
    else mode = "ACRO"
    end
end

local function drawFooter()
    lcd.drawLine(0, FOOTER_Y, 212, FOOTER_Y, SOLID, FORCE)

    local datetime = getDateTime()
    lcd.drawText(3, FOOTER_Y + FOOTER_TEXT_OFFSET,
        string.format("%.2d:%.2d:%.2d",
        datetime.hour, datetime.min, datetime.sec),
        SMLSIZE)

    local batt = getValue("tx-voltage")
    local settings = getGeneralSettings()
    lcd.drawPixmap(43, FOOTER_Y + 2, "/SCRIPTS/BMP/batt.bmp")
    local fill = 20 * (batt - settings.battMin) / (settings.battMax - settings.battMin)

    fill = math.max(math.min(20, fill), 0)
    if (fill > 0) then
        lcd.drawFilledRectangle(44, FOOTER_Y + 3, fill, 6, 0)
    end

    local v = string.format("%.1fV", batt, 3)
    lcd.drawText(70, FOOTER_Y + FOOTER_TEXT_OFFSET, v, SMLSIZE)

    lcd.drawText(100, FOOTER_Y + FOOTER_TEXT_OFFSET,
        mode, SMLSIZE)

    lcd.drawText(131, FOOTER_Y + FOOTER_TEXT_OFFSET,
        string.format("%dmAh", mah), SMLSIZE)

    lcd.drawText(173, FOOTER_Y + FOOTER_TEXT_OFFSET,
        string.format("%dS", cells), SMLSIZE)

    lcd.drawText(188, FOOTER_Y + FOOTER_TEXT_OFFSET,
        string.format("%.1fV", low), SMLSIZE)
end

local function drawTimers()
    local t1 = model.getTimer(0).value
    local t2 = model.getTimer(1).value
    lcd.drawText(6, 12, formatTime(t1), MIDSIZE)
    lcd.drawText(6, 32, formatTime(t2), MIDSIZE)
end

local function drawFuel()
    local xoffset = 72
    local vfas = getValue("VFAS")
    local fuel = getValue("Fuel")

    lcd.drawPixmap(xoffset, 6, "/SCRIPTS/BMP/vfas.bmp")

    local max_height = 33
    local fill = max_height * (vfas - low) / (high - low)

    fill = round(math.max(math.min(max_height, fill), 0))
    if (fill > 0) then
        lcd.drawFilledRectangle(xoffset + 3, 12 + max_height - fill, 13, fill, 0)
    end

    fill = round(math.max(math.min(max_height, max_height * (mah - fuel) / mah), 0))
    if (fill > 0) then
        lcd.drawFilledRectangle(xoffset + 3 + 14, 12 + max_height - fill, 4, fill, 0)
    end

    lcd.drawText(xoffset + 30, 4, string.format("%5.2f", vfas), MIDSIZE)
    lcd.drawText(lcd.getLastPos(), 8, "V", 0)

    lcd.drawText(xoffset + 30, 20, string.format("%04d", fuel), MIDSIZE)
    lcd.drawText(lcd.getLastPos(), 24, "mAh", 0)

    lcd.drawText(xoffset + 30, 37, "00:00:00", MIDSIZE)
end

local function drawRSSI()
    local rssi = getValue("RSSI")

    local p = round(9 * (rssi - 45) / (90 - 45))
    local f = math.max(math.min(8, p - 1), 0)
    lcd.drawPixmap(175, 20, "/SCRIPTS/BMP/signal_" .. f .. ".bmp")

    local rssi = getValue("RSSI")
    lcd.drawText(180, 34, rssi, 0)
end

local function drawArm()
    if armed then
        lcd.drawText(177, 7, "ARMED", SMLSIZE)
    end
end

local function next_battery()
    batt_index = batt_index + 1
    if batt_index > #batteries then
        batt_index = 1
    end
end

local function prev_battery()
    batt_index = batt_index - 1
    if batt_index == 0 then
        batt_index = #batteries
    end
end

local function update()
    mah = batteries[batt_index].mah
    cells = batteries[batt_index].cells
    high = batteries[batt_index].high
    low = batteries[batt_index].low
end

local function battery_down()
    if batt_index < #batteries then
        batteries[batt_index], batteries[batt_index + 1] =
            batteries[batt_index + 1], batteries[batt_index]
        next_battery()
    end
end

local function battery_up()
    if batt_index > 0 then
        batteries[batt_index], batteries[batt_index - 1] =
            batteries[batt_index - 1], batteries[batt_index]
        prev_battery()
    end
end

local EDIT_MODE_NONE = 0
local EDIT_MODE_SELECT = 1
local EDIT_MODE_EDIT = 2

local edit_index = 1
local edit_mode = EDIT_MODE_NONE
local edit_index_max = 5

local function next_edit()
    if edit_index > 1 then
        edit_index = edit_index - 1
    end
end

local function prev_edit()
    if edit_index < edit_index_max then
        edit_index = edit_index + 1
    end
end

local BATT_SCR_MODE_SHOW = 0
local BATT_SCR_MODE_EDIT = 1
local BATT_SCR_MODE_MOVE = 2
local BATT_SCR_MODE_NEW  = 3

local batt_screen_mode = 0
local flags = 0

local function set_flags(x, y)
    if batt_index == x then
        if edit_mode == EDIT_MODE_SELECT then
            if edit_index == y then
                flags = INVERS
            else
                flags = 0
            end
        elseif edit_mode == EDIT_MODE_EDIT then
            if edit_index == y then
                flags = INVERS + BLINK
            else
                flags = 0
            end
        else
            flags = INVERS
        end
    else
        flags = 0
    end
end

local function show_batteries(event)
    -- NOTE: BATT_SCR_MODE_EDIT and edit_mode hold similar info - combine these two?
    if event == EVT_PLUS_FIRST then
        if batt_screen_mode == BATT_SCR_MODE_EDIT then
            if edit_mode == EDIT_MODE_EDIT then
                if edit_index == 1 then
                    battery_up()
                end
            else
                prev_edit()
            end
        else
            prev_battery()
        end
    elseif event == EVT_MINUS_FIRST then
        if batt_screen_mode == BATT_SCR_MODE_EDIT then
            if edit_mode == EDIT_MODE_EDIT then
                if edit_index == 1 then
                    battery_down()
                end
            else
                next_edit()
            end
        else
            next_battery()
        end
    elseif event == EVT_ENTER_BREAK then
        if edit_mode == EDIT_MODE_NONE then
            batt_screen_mode = BATT_SCR_MODE_EDIT
            edit_mode = EDIT_MODE_SELECT
            edit_index = 1
        elseif edit_mode == EDIT_MODE_SELECT then
            edit_mode = EDIT_MODE_EDIT
        else
            edit_mode = EDIT_MODE_SELECT
        end
    elseif event == EVT_EXIT_BREAK then
        batt_screen_mode = BATT_SCR_MODE_SHOW
        edit_mode = EDIT_MODE_NONE
    end

    lcd.clear()

    for i=1,#batteries do
        local y = 4 + (i-1)*10
        local x = 5
        set_flags(i, 1)
        if batt_screen_mode == BATT_SCR_MODE_EDIT then
            if i == batt_index then
                lcd.drawText(x, y, "[=]", flags)
                set_flags(i, 0)
                lcd.drawText(lcd.getLastPos(), y, " ", flags)
                x = lcd.getLastPos()
            end
        end

        set_flags(i, 2)
        lcd.drawText(x, y, string.format("%dmAh", batteries[i].mah), flags)
        set_flags(i, 0)
        lcd.drawText(lcd.getLastPos(), y, ", ", flags)
        set_flags(i, 3)
        lcd.drawText(lcd.getLastPos(), y, string.format("%dS", batteries[i].cells), flags)
        set_flags(i, 0)
        lcd.drawText(lcd.getLastPos(), y, ", ", flags)
        set_flags(i, 4)
        lcd.drawText(lcd.getLastPos(), y, string.format("%.1fV", batteries[i].low), flags)
        set_flags(i, 0)
        lcd.drawText(lcd.getLastPos(), y, " - ", flags)
        set_flags(i, 5)
        lcd.drawText(lcd.getLastPos(), y, string.format("%.1fV", batteries[i].high), flags)
    end
end

local function show_main(event)
    lcd.clear()

    if event == EVT_PLUS_FIRST then
        next_battery()
    elseif event == EVT_MINUS_FIRST then
        prev_battery()
    end

    parseTmp1()
    update()

    drawFooter()
    drawTimers()
    drawFuel()
    drawRSSI()
    drawArm()
end

local screen = 1

local function run(event)
    if event == EVT_MENU_BREAK then
        screen = screen + 1
        if screen > 1 then
            save_batteries()
            screen = 0
        end
    end

    if screen == 0 then
        show_main(event)
    elseif screen == 1 then
        show_batteries(event)
    end
end

local function init()
    dofile(BATT_FILE)
end

local function background() end

return{run=run, background=background, init=init}
-- ** LOCAL UTIL **
local function repair_subfactory(player, _, _)
    -- This function can only run is a subfactory is selected and invalid
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]
    subfactory:repair(player)

    solver.update(player, subfactory)
    util.raise.refresh(player, "all", nil)  -- needs the full refresh to reset subfactory list buttons
end

local function change_timescale(player, new_timescale)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    local timescale_ratio = (new_timescale / factory.timescale)
    factory.timescale = new_timescale

    -- Adjust the required_amount according to the new timescale
    for product in factory:iterator() do
        -- No need to change amounts for belts/lanes, as timescale change does that implicitly
        if product.defined_by == "amount" then
            product.required_amount = product.required_amount * timescale_ratio
        end
    end

    solver.update(player, factory)
    -- View state updates itself automatically if it detects a timescale change
    util.raise.refresh(player, "subfactory", nil)
end

local function handle_solver_change(player, _, event)
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]
    local new_solver = (event.element.switch_state == "left") and "traditional" or "matrix"

    if new_solver == "matrix" then
        subfactory.matrix_free_items = {}  -- activate the matrix solver
    else
        subfactory.matrix_free_items = nil  -- disable the matrix solver
        subfactory.linearly_dependant = false

        local any_lines_removed = subfactory.top_floor:remove_consuming_lines()
        if any_lines_removed then  -- inform the user if any byproduct recipes are being removed
            util.messages.raise(player, "hint", {"fp.hint_byproducts_removed"}, 1)
        end
    end

    solver.update(player, subfactory)
    util.raise.refresh(player, "subfactory", nil)
end


local function refresh_subfactory_info(player)
    local main_elements = util.globals.main_elements(player)
    if main_elements.main_frame == nil then return end

    local subfactory_info_elements = main_elements.subfactory_info
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory?]]

    local invalid_subfactory_selected = (subfactory and not subfactory.valid)
    subfactory_info_elements.repair_flow.visible = invalid_subfactory_selected

    local valid_subfactory_selected = (subfactory and subfactory.valid)
    subfactory_info_elements.power_pollution_flow.visible = valid_subfactory_selected
    subfactory_info_elements.info_flow.visible = valid_subfactory_selected

    if subfactory == nil then return end

    if invalid_subfactory_selected then
        subfactory_info_elements.repair_label.tooltip = util.porter.format_modset_diff(subfactory.last_valid_modset)

    elseif valid_subfactory_selected then  -- we need to refresh some stuff in this case
        -- Power + Pollution
        local top_floor = subfactory.top_floor
        local label_power = subfactory_info_elements.power_label
        label_power.caption = {"fp.bold_label", util.format.SI_value(top_floor.power, "W", 3)}
        label_power.tooltip = util.format.SI_value(top_floor.power, "W", 5)

        local label_pollution = subfactory_info_elements.pollution_label
        label_pollution.caption = {"fp.bold_label", util.format.SI_value(top_floor.pollution, "P/m", 3)}
        label_pollution.tooltip = util.format.SI_value(top_floor.pollution, "P/m", 5)

        -- Timescale
        for _, button in pairs(subfactory_info_elements.timescales_table.children) do
            button.toggled = (subfactory.timescale == button.tags.timescale)
        end

        -- Mining Productivity
        local archive_open = subfactory.archived
        local custom_prod_set = subfactory.mining_productivity

        if not custom_prod_set then  -- only do this calculation when it'll actually be shown
            local prod_bonus = util.format.number((player.force.mining_drill_productivity_bonus * 100), 4)
            subfactory_info_elements.prod_bonus_label.caption = {"fp.bold_label", prod_bonus .. "%"}
        end
        subfactory_info_elements.prod_bonus_label.visible = not custom_prod_set

        subfactory_info_elements.override_prod_bonus_button.enabled = (not archive_open)
        subfactory_info_elements.override_prod_bonus_button.visible = not custom_prod_set

        if custom_prod_set then  -- only change the text when the textfield will actually be shown
            subfactory_info_elements.prod_bonus_override_textfield.text = tostring(subfactory.mining_productivity)
        end
        subfactory_info_elements.prod_bonus_override_textfield.enabled = (not archive_open)
        subfactory_info_elements.prod_bonus_override_textfield.visible = custom_prod_set
        subfactory_info_elements.percentage_label.visible = custom_prod_set

        -- Solver Choice
        local matrix_solver_active = (subfactory.matrix_free_items ~= nil)
        local switch_state = (matrix_solver_active) and "right" or "left"
        subfactory_info_elements.solver_choice_switch.switch_state = switch_state
        subfactory_info_elements.solver_choice_switch.enabled = (not archive_open)
        subfactory_info_elements.configure_solver_button.enabled = (not archive_open and matrix_solver_active)
    end
end

local function build_subfactory_info(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.subfactory_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical",
        style="inside_shallow_frame_with_padding"}
    frame_vertical.style.size = {MAGIC_NUMBERS.list_width, MAGIC_NUMBERS.info_height}

    local flow_title = frame_vertical.add{type="flow", direction="horizontal"}
    flow_title.style.margin = {-4, 0, 8, 0}
    flow_title.add{type="label", caption={"fp.subfactory_info"}, style="caption_label"}
    flow_title.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Power + Pollution
    local flow_power_pollution = flow_title.add{type="flow", direction="horizontal"}
    main_elements.subfactory_info["power_pollution_flow"] = flow_power_pollution
    local label_power_value = flow_power_pollution.add{type="label"}
    main_elements.subfactory_info["power_label"] = label_power_value
    flow_power_pollution.add{type="label", caption="|"}
    local label_pollution_value = flow_power_pollution.add{type="label"}
    main_elements.subfactory_info["pollution_label"] = label_pollution_value


    -- Repair flow
    local flow_repair = frame_vertical.add{type="flow", direction="vertical"}
    flow_repair.style.top_margin = -2
    main_elements.subfactory_info["repair_flow"] = flow_repair

    local label_repair = flow_repair.add{type="label", caption={"fp.warning_with_icon", {"fp.subfactory_needs_repair"}}}
    label_repair.style.single_line = false
    main_elements.subfactory_info["repair_label"] = label_repair

    local button_repair = flow_repair.add{type="button", tags={mod="fp", on_gui_click="repair_subfactory"},
        caption={"fp.repair_subfactory"}, style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    button_repair.style.top_margin = 2


    -- Subfactory info
    local flow_info = frame_vertical.add{type="flow", direction="vertical"}
    flow_info.style.vertical_spacing = 8
    main_elements.subfactory_info["info_flow"] = flow_info

    -- Timescale
    local flow_timescale = flow_info.add{type="flow", direction="horizontal"}
    flow_timescale.style.horizontal_spacing = 10
    flow_timescale.style.vertical_align = "center"

    flow_timescale.add{type="label", caption={"fp.info_label", {"fp.timescale"}}, tooltip={"fp.timescale_tt"}}
    flow_timescale.add{type="empty-widget", style="flib_horizontal_pusher"}


    local timescale_map = {[1] = "second", [60] = "minute", [3600] = "hour"}
    local table_timescales = flow_timescale.add{type="table", column_count=table_size(timescale_map)}
    table_timescales.style.horizontal_spacing = 0
    main_elements.subfactory_info["timescales_table"] = table_timescales

    for scale, name in pairs(timescale_map) do
        local button = table_timescales.add{type="button", caption={"", "1", {"fp.unit_" .. name}},
            tags={mod="fp", on_gui_click="change_timescale", timescale=scale},
            style="fp_button_push", mouse_button_filter={"left"}}
        button.style.width = 42
    end

    -- Mining productivity
    local flow_mining_prod = flow_info.add{type="flow", direction="horizontal"}
    flow_mining_prod.style.horizontal_spacing = 10
    flow_mining_prod.style.vertical_align = "center"

    flow_mining_prod.add{type="label", caption={"fp.info_label", {"fp.mining_productivity"}},
        tooltip={"fp.mining_productivity_tt"}}
    flow_mining_prod.add{type="empty-widget", style="flib_horizontal_pusher"}

    local label_prod_bonus = flow_mining_prod.add{type="label"}
    main_elements.subfactory_info["prod_bonus_label"] = label_prod_bonus

    local button_override_prod_bonus = flow_mining_prod.add{type="button", caption={"fp.override"},
        tags={mod="fp", on_gui_click="override_mining_prod"}, style="fp_button_rounded_mini",
        mouse_button_filter={"left"}}
    button_override_prod_bonus.style.disabled_font_color = {}
    main_elements.subfactory_info["override_prod_bonus_button"] = button_override_prod_bonus

    local textfield_prod_bonus = flow_mining_prod.add{type="textfield",
        tags={mod="fp", on_gui_text_changed="mining_prod_override", on_gui_confirmed="mining_prod_override"}}
    textfield_prod_bonus.style.size = {60, 26}
    util.gui.setup_numeric_textfield(textfield_prod_bonus, true, true)
    main_elements.subfactory_info["prod_bonus_override_textfield"] = textfield_prod_bonus

    local label_percentage = flow_mining_prod.add{type="label", caption={"fp.bold_label", "%"}}
    main_elements.subfactory_info["percentage_label"] = label_percentage

    -- Solver Choice
    local flow_solver_choice = flow_info.add{type="flow", direction="horizontal"}
    flow_solver_choice.style.horizontal_spacing = 10
    flow_solver_choice.style.vertical_align = "center"

    flow_solver_choice.add{type="label", caption={"fp.info_label", {"fp.solver_choice"}},
        tooltip={"fp.solver_choice_tt"}}
    flow_solver_choice.add{type="empty-widget", style="flib_horizontal_pusher"}

    local switch_solver_choice = flow_solver_choice.add{type="switch", right_label_caption={"fp.solver_choice_matrix"},
        left_label_caption={"fp.solver_choice_traditional"},
        tags={mod="fp", on_gui_switch_state_changed="solver_choice_changed"}}
    main_elements.subfactory_info["solver_choice_switch"] = switch_solver_choice

    local button_configure_solver = flow_solver_choice.add{type="sprite-button", sprite="utility/change_recipe",
        tooltip={"fp.solver_choice_configure"}, tags={mod="fp", on_gui_click="configure_matrix_solver"},
        style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    button_configure_solver.style.size = 26
    button_configure_solver.style.padding = 0
    main_elements.subfactory_info["configure_solver_button"] = button_configure_solver

    refresh_subfactory_info(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "repair_subfactory",
            timeout = 20,
            handler = repair_subfactory
        },
        {
            name = "change_timescale",
            handler = (function(player, tags, _)
                change_timescale(player, tags.timescale)
            end)
        },
        {
            name = "override_mining_prod",
            handler = (function(player, _, _)
                local subfactory = util.context.get(player, "Factory")
                subfactory.mining_productivity = 0
                solver.update(player, subfactory)
                util.raise.refresh(player, "subfactory", nil)
            end)
        },
        {
            name = "configure_matrix_solver",
            handler = (function(player, _, _)
                util.raise.open_dialog(player, {dialog="matrix", modal_data={configuration=true}})
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "mining_prod_override",
            handler = (function(player, _, event)
                util.context.get(player, "Factory").mining_productivity = tonumber(event.element.text)
                util.globals.flags(player).recalculate_on_subfactory_change = true  -- set flag to recalculate
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "solver_choice_changed",
            handler = handle_solver_change
        }
    },
    on_gui_confirmed = {
        {
            name = "mining_prod_override",
            handler = (function(player, _, _)
                -- Reset the recalculation flag as we re-solve below
                util.globals.flags(player).recalculate_on_subfactory_change = false
                solver.update(player)
                util.raise.refresh(player, "subfactory", nil)
            end)
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_subfactory_info(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {subfactory_info=true, subfactory=true, all=true}
        if triggers[event.trigger] then refresh_subfactory_info(player) end
    end)
}

return { listeners }

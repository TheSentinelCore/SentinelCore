local RotationTab = {}

---@param ui any
---@param menu table
---@param profile_labels string[]
function RotationTab.register(ui, menu, profile_labels)
    ui:add_tab({ id = "rotation", label = "Rotation" }, function(t)
        t:checkbox_grid({
            label = "Mode",
            columns = 1,
            elements = {
                {
                    element = menu.auto_rotation,
                    label = "Auto Select By Class",
                    tooltip = "When enabled, GrindBuddy selects a TBC profile matching your class automatically.",
                },
            },
        })

        t:combo_list({
            label = "Manual Profile",
            elements = {
                {
                    element = menu.rotation_profile,
                    label = "Profile",
                    options = profile_labels,
                    tooltip = "Manual profile used when Auto Select is disabled.",
                },
            },
        })
    end)
end

return RotationTab

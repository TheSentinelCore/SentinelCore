local Schema = {}

Schema.allowed_roots = {
    system = true,
    player = true,
    combat = true,
    rotation = true,
    bg = true,
    nav = true,
    module = true,
}

local function split_first(key)
    local root, rest = tostring(key):match("^([^.]+)%.(.*)$")
    return root, rest
end

function Schema.validate_key(key)
    if type(key) ~= "string" or key == "" then
        return false, "key_must_be_non_empty_string"
    end
    local root, rest = split_first(key)
    if not Schema.allowed_roots[root] then
        return false, "root_not_allowed"
    end
    if root == "module" then
        local module_name = rest and rest:match("^([^.]+)")
        if not module_name or module_name == "" then
            return false, "module_namespace_requires_module_name_and_key"
        end
    end
    return true, nil
end

return Schema

-- Liberium Hub | Resource lifetime manager
-- Shared cleanup primitive for UI pages, controls, input bindings and feature sessions.

local Maid = {}
Maid.__index = Maid

local function dispose(resource)
    if resource == nil then
        return
    end

    local kind = typeof(resource)
    if kind == "RBXScriptConnection" then
        pcall(function()
            resource:Disconnect()
        end)
        return
    end

    if kind == "Instance" then
        pcall(function()
            resource:Destroy()
        end)
        return
    end

    if type(resource) == "function" then
        pcall(resource)
        return
    end

    if type(resource) == "thread" then
        pcall(task.cancel, resource)
        return
    end

    if type(resource) == "table" then
        local cleanup = resource.Destroy or resource.Disconnect or resource.Cleanup or resource.Clean
        if type(cleanup) == "function" then
            pcall(cleanup, resource)
        end
    end
end

function Maid.new()
    return setmetatable({
        _tasks = {},
        _nextId = 0,
        _destroyed = false,
    }, Maid)
end

function Maid:Give(resource, key)
    if resource == nil then
        return nil
    end

    if self._destroyed then
        dispose(resource)
        return resource
    end

    if key ~= nil then
        self:Remove(key)
        self._tasks[key] = resource
    else
        self._nextId += 1
        self._tasks[self._nextId] = resource
    end

    return resource
end

function Maid:Connect(signal, callback, key)
    assert(signal ~= nil and type(callback) == "function", "Maid:Connect expects a signal and callback")
    return self:Give(signal:Connect(callback), key)
end

function Maid:Remove(key)
    local resource = self._tasks[key]
    self._tasks[key] = nil
    dispose(resource)
end

function Maid:Clean()
    for key, resource in pairs(self._tasks) do
        self._tasks[key] = nil
        dispose(resource)
    end
end

function Maid:Destroy()
    if self._destroyed then
        return
    end

    self._destroyed = true
    self:Clean()
end

function Maid:IsDestroyed()
    return self._destroyed
end

return Maid

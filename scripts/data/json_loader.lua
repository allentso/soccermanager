-- data/json_loader.lua
-- JSON数据加载器

local JsonLoader = {}

function JsonLoader.loadFromResource(path)
    local file = cache:GetFile(path)
    if not file then
        log:Write(LOG_ERROR, "JsonLoader: 无法加载文件 " .. path)
        return nil
    end
    local content = file:ReadString()
    if not content or content == "" then
        log:Write(LOG_ERROR, "JsonLoader: 文件内容为空 " .. path)
        return nil
    end
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        log:Write(LOG_ERROR, "JsonLoader: JSON解析失败 " .. path .. " - " .. tostring(data))
        return nil
    end
    return data
end

function JsonLoader.loadTeams()
    local data = JsonLoader.loadFromResource("Data/default_teams.json")
    if data and data.teams then
        return data.teams
    end
    return nil
end

function JsonLoader.loadNames()
    local data = JsonLoader.loadFromResource("Data/default_names.json")
    if data and data.pools then
        return data.pools
    end
    return nil
end

function JsonLoader.encode(data)
    local ok, result = pcall(cjson.encode, data)
    if ok then return result end
    log:Write(LOG_ERROR, "JsonLoader: JSON编码失败 - " .. tostring(result))
    return nil
end

function JsonLoader.decode(str)
    local ok, result = pcall(cjson.decode, str)
    if ok then return result end
    return nil
end

return JsonLoader

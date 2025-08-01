prp = prp or {}
prp.ModuleLoader = prp.ModuleLoader or {}

prp.ModuleLoader.LoadedModules = {}
prp.ModuleLoader.ModuleDependencies = {}
prp.ModuleLoader.LoadOrder = {}

if not prp.Util then
    prp.Util = {}
    function prp.Util:Log(message, level)
        local timestamp = os.date("%H:%M:%S")
        local levelStr = level or "INFO"
        print(string.format("[%s] [%s] %s", timestamp, levelStr, message))
    end
end

prp.ModuleLoader.Folders = {
    ['gamemode']    = 'gamemode/',
    ['configs']     = 'gamemode/configs/',
    ['core']        = 'gamemode/core/',
    ['modules']     = 'gamemode/modules/'
}

prp.ModuleLoader.FileTypes = {
    ['sh_'] = 'shared',
    ['sv_'] = 'server', 
    ['cl_'] = 'client'
}

local moduleCounter = 0

function prp.ModuleLoader:GetNextModuleID()
    moduleCounter = moduleCounter + 1
    return moduleCounter
end

function prp.ModuleLoader:GetFileType(fileName)
    for prefix, fileType in pairs(self.FileTypes) do
        if fileName:sub(1, #prefix) == prefix then
            return fileType
        end
    end
    return 'unknown'
end

function prp.ModuleLoader:ExtractFileName(filePath)
    if not filePath then return "unknown" end
    filePath = filePath:gsub("^@", "")
    local fileName = filePath:match("([^/\\]+)$")
    return fileName or "unknown"
end

function prp.ModuleLoader:ExtractDirectory(filePath)
    if not filePath then return "" end
    filePath = filePath:gsub("^@", "")
    local directory = filePath:match("(.*[/\\])")
    return directory or ""
end

function prp.ModuleLoader:ExtractModuleName(filePath)
    if not filePath then return "unknown" end
    
    local modulePath = filePath:match("modules/([^/]+)")
    if modulePath then
        return modulePath
    end
    
    local pathParts = {}
    for part in filePath:gmatch("[^/]+") do
        table.insert(pathParts, part)
    end
    
    for i, part in ipairs(pathParts) do
        if part == "modules" and pathParts[i + 1] then
            return pathParts[i + 1]
        end
    end
    
    if #pathParts > 1 then
        return pathParts[#pathParts - 1]
    end
    
    return "unknown"
end

function prp.ModuleLoader:AddLoadedModule(filePath, fileType, dependencies, loadMethod)
    for _, existingModule in pairs(self.LoadedModules) do
        if existingModule.fullPath == filePath then
            if prp and prp.Util and prp.Util.Log then
                prp.Util:Log("File already loaded, skipping: " .. filePath, "WARNING")
            end
            return existingModule.id
        end
    end
    
    local moduleID = self:GetNextModuleID()
    local fileName = self:ExtractFileName(filePath)
    local directory = self:ExtractDirectory(filePath)
    local moduleName = self:ExtractModuleName(filePath)
    
    local moduleData = {
        id = moduleID,
        name = fileName,
        fullPath = filePath,
        directory = directory,
        moduleName = moduleName,
        fileType = fileType,
        loadTime = os.time(),
        dependencies = dependencies or {},
        isLoaded = true,
        loadMethod = loadMethod or "unknown"
    }
    
    self.LoadedModules[moduleID] = moduleData
    table.insert(self.LoadOrder, moduleID)
    
    if not self.ModuleDependencies[moduleName] then
        self.ModuleDependencies[moduleName] = {}
    end
    self.ModuleDependencies[moduleName][fileName] = moduleData
    
    return moduleID
end

function prp.ModuleLoader:CheckDependencies(moduleName, dependencies)
    if not dependencies or #dependencies == 0 then
        return true
    end
    
    for _, dep in ipairs(dependencies) do
        local found = false
        for _, moduleData in pairs(self.LoadedModules) do
            if moduleData.name == dep then
                found = true
                break
            end
        end
        if not found then
            if prp and prp.Util and prp.Util.Log then
                prp.Util:Log("Dependency not found: " .. dep .. " for module " .. moduleName, "ERROR")
            end
            return false
        end
    end
    
    return true
end

function prp.ModuleLoader:LoadFile(filePath, fileType, dependencies)
    local loadMethod = "unknown"
    
    if fileType == 'shared' then
        include(filePath)
        AddCSLuaFile(filePath)
        loadMethod = "both"
    elseif fileType == 'server' then
        include(filePath)
        loadMethod = "include"
    elseif fileType == 'client' then
        AddCSLuaFile(filePath)
        loadMethod = "AddCSLuaFile"
    end
    
    local moduleID = self:AddLoadedModule(filePath, fileType, dependencies, loadMethod)
    
    if prp and prp.Util and prp.Util.Log then
        prp.Util:Log("Loaded " .. fileType .. " file: " .. filePath .. " (" .. loadMethod .. ")", "INFO")
    end
    
    return moduleID
end

function prp.ModuleLoader:LoadModule(modulePath, dependencies)
    local files = {}
    local fol = GM.FolderName .. "/" .. modulePath
    
    for prefix, fileType in pairs(self.FileTypes) do
        local pattern = fol .. "/" .. prefix .. "*.lua"
        for _, fileName in SortedPairs(file.Find(pattern, "LUA"), true) do
            if fileName:match("interface%.lua$") then continue end
            
            local filePath = modulePath .. "/" .. fileName
            local fullPath = fol .. "/" .. fileName
            
            if self:CheckDependencies(fileName, dependencies) then
                self:LoadFile(fullPath, fileType, dependencies)
            else
                if prp and prp.Util and prp.Util.Log then
                    prp.Util:Log("Skipping " .. fileName .. " due to missing dependencies", "WARNING")
                end
            end
        end
    end
end

function prp.ModuleLoader:LoadAllModules()
    local fol = ""
    if GM and GM.FolderName then
        fol = GM.FolderName .. "/gamemode/modules/"
    elseif GAMEMODE and GAMEMODE.FolderName then
        fol = GAMEMODE.FolderName .. "/gamemode/modules/"
    else
        fol = "gamemodes/purpur-master/gamemode/modules/"
    end
    
    local function FindAllFiles(basePath, currentPath)
        local files = {}
        local folders = {}
        
        local items, dirs = file.Find(basePath .. currentPath .. "*", "LUA")
        
        if items then
            for _, item in pairs(items) do
                if item:match("%.lua$") then
                    local fullPath = currentPath .. item
                    local relativePath = "modules/" .. fullPath
                    table.insert(files, {
                        fullPath = basePath .. fullPath,
                        relativePath = relativePath,
                        fileName = item,
                        modulePath = currentPath:gsub("/$", "")
                    })
                end
            end
        end
        
        if dirs then
            for _, dir in pairs(dirs) do
                if dir ~= "." and dir ~= ".." then
                    local subFiles = FindAllFiles(basePath, currentPath .. dir .. "/")
                    for _, file in pairs(subFiles) do
                        table.insert(files, file)
                    end
                end
            end
        end
        
        return files
    end
    
    local allFiles = FindAllFiles(fol, "")
    
    if #allFiles == 0 then
        if prp and prp.Util and prp.Util.Log then
            prp.Util:Log("No modules found in modules folder", "WARNING")
        end
        return
    end
    
    local filePriority = {
        ["sh_"] = 1,
        ["sv_"] = 2,
        ["cl_"] = 3
    }
    
    table.sort(allFiles, function(a, b)
        local aPrefix = a.fileName:sub(1, 3)
        local bPrefix = b.fileName:sub(1, 3)
        local aPriority = filePriority[aPrefix] or 999
        local bPriority = filePriority[bPrefix] or 999
        
        if aPriority == bPriority then
            return a.fileName < b.fileName
        end
        return aPriority < bPriority
    end)
    
    for _, fileInfo in ipairs(allFiles) do
        local fileName = fileInfo.fileName
        local fullPath = fileInfo.fullPath
        local relativePath = fileInfo.relativePath
        local modulePath = fileInfo.modulePath
        
        local fileType = "unknown"
        for prefix, type in pairs(self.FileTypes) do
            if fileName:sub(1, #prefix) == prefix then
                fileType = type
                break
            end
        end
        
        if fileName:match("interface%.lua$") then
            if prp and prp.Util and prp.Util.Log then
                prp.Util:Log("Skipping interface file: " .. fileName, "INFO")
            end
        else
            local loadMethod = "unknown"
            
            if fileType == 'shared' then
                include(fullPath)
                AddCSLuaFile(fullPath)
                loadMethod = "both"
            elseif fileType == 'server' then
                include(fullPath)
                loadMethod = "include"
            elseif fileType == 'client' then
                AddCSLuaFile(fullPath)
                loadMethod = "AddCSLuaFile"
            end
            
            self:AddLoadedModule(relativePath, fileType, {}, loadMethod)
            
            if prp and prp.Util and prp.Util.Log then
                prp.Util:Log("Loaded " .. fileType .. " file: " .. relativePath .. " (" .. loadMethod .. ")", "INFO")
            end
        end
    end
    
    if prp and prp.Util and prp.Util.Log then
        prp.Util:Log("Total modules loaded: " .. #allFiles, "INFO")
    end
end

function prp.ModuleLoader:RegisterExistingFile(filePath, fileType, dependencies, loadMethod)
    local moduleID = self:AddLoadedModule(filePath, fileType, dependencies, loadMethod)
    
    if prp and prp.Util and prp.Util.Log then
        prp.Util:Log("Registered existing file: " .. filePath .. " (" .. (loadMethod or "unknown") .. ")", "INFO")
    end
    
    return moduleID
end

concommand.Add("prp_modules_list", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    print("=== Загруженные модули ===")
    print(string.format("%-5s %-20s %-15s %-10s %-15s %-30s", "ID", "Имя файла", "Тип", "Модуль", "Метод загрузки", "Путь"))
    print(string.rep("-", 100))
    
    for moduleID, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
        print(string.format("%-5s %-20s %-15s %-10s %-15s %-30s", 
            moduleID, 
            moduleData.name:sub(1, 18), 
            moduleData.fileType, 
            moduleData.moduleName:sub(1, 8),
            moduleData.loadMethod,
            moduleData.fullPath:sub(1, 28)
        ))
    end
    
    print("Всего загружено модулей: " .. moduleCounter)
end)

concommand.Add("prp_modules_by_type", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    local fileType = args[1] or "all"
    
    print("=== Модули по типу: " .. fileType .. " ===")
    
    for moduleID, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
        if fileType == "all" or moduleData.fileType == fileType then
            print(string.format("[%d] %s (%s) - %s [%s]", 
                moduleID, 
                moduleData.name, 
                moduleData.fileType, 
                moduleData.moduleName,
                moduleData.loadMethod
            ))
        end
    end
end)

concommand.Add("prp_module_deps", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    local moduleName = args[1]
    if not moduleName then
        print("Использование: prp_module_deps <имя_модуля>")
        return
    end
    
    print("=== Зависимости модуля: " .. moduleName .. " ===")
    
    if prp.ModuleLoader.ModuleDependencies[moduleName] then
        for fileName, moduleData in pairs(prp.ModuleLoader.ModuleDependencies[moduleName]) do
            print(string.format("- %s (%s) [%s]", fileName, moduleData.fileType, moduleData.loadMethod))
            if moduleData.dependencies and #moduleData.dependencies > 0 then
                print("  Зависимости: " .. table.concat(moduleData.dependencies, ", "))
            end
        end
    else
        print("Модуль не найден")
    end
end)

concommand.Add("prp_load_order", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    print("=== Порядок загрузки модулей ===")
    
    for i, moduleID in ipairs(prp.ModuleLoader.LoadOrder) do
        local moduleData = prp.ModuleLoader.LoadedModules[moduleID]
        if moduleData then
            print(string.format("[%d] %s (%s) [%s]", i, moduleData.name, moduleData.fileType, moduleData.loadMethod))
        end
    end
end)

concommand.Add("prp_modules_stats", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    local stats = {
        total = 0,
        shared = 0,
        server = 0,
        client = 0,
        modules = {},
        loadMethods = {
            include = 0,
            AddCSLuaFile = 0,
            both = 0,
            unknown = 0
        }
    }
    
    for moduleID, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
        stats.total = stats.total + 1
        stats[moduleData.fileType] = stats[moduleData.fileType] + 1
        
        if stats.loadMethods[moduleData.loadMethod] then
            stats.loadMethods[moduleData.loadMethod] = stats.loadMethods[moduleData.loadMethod] + 1
        end
        
        if not stats.modules[moduleData.moduleName] then
            stats.modules[moduleData.moduleName] = 0
        end
        stats.modules[moduleData.moduleName] = stats.modules[moduleData.moduleName] + 1
    end
    
    print("=== Статистика загруженных модулей ===")
    print("Всего файлов: " .. stats.total)
    print("Shared файлов: " .. stats.shared)
    print("Server файлов: " .. stats.server)
    print("Client файлов: " .. stats.client)
    print("\nПо методам загрузки:")
    print("- include: " .. stats.loadMethods.include)
    print("- AddCSLuaFile: " .. stats.loadMethods.AddCSLuaFile)
    print("- both: " .. stats.loadMethods.both)
    print("- unknown: " .. stats.loadMethods.unknown)
    print("\nПо модулям:")
    
    for moduleName, count in pairs(stats.modules) do
        print("- " .. moduleName .. ": " .. count .. " файлов")
    end
end)

concommand.Add("prp_clean_duplicates", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    print("=== Очистка дублированных записей ===")
    
    local duplicates = {}
    local uniqueModules = {}
    local removedCount = 0
    
    for moduleID, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
        local key = moduleData.fullPath
        if uniqueModules[key] then
            table.insert(duplicates, moduleID)
            removedCount = removedCount + 1
        else
            uniqueModules[key] = moduleData
        end
    end
    
    for _, moduleID in ipairs(duplicates) do
        prp.ModuleLoader.LoadedModules[moduleID] = nil
    end
    
    local newLoadOrder = {}
    for _, moduleID in ipairs(prp.ModuleLoader.LoadOrder) do
        if prp.ModuleLoader.LoadedModules[moduleID] then
            table.insert(newLoadOrder, moduleID)
        end
    end
    prp.ModuleLoader.LoadOrder = newLoadOrder
    
    print("Удалено дублированных записей: " .. removedCount)
    print("Осталось уникальных модулей: " .. table.Count(prp.ModuleLoader.LoadedModules))
end)

concommand.Add("prp_register_file", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    local filePath = args[1]
    local fileType = args[2] or "shared"
    
    if not filePath then
        print("Использование: prp_register_file <путь_к_файлу> [тип]")
        return
    end
    
    prp.ModuleLoader:RegisterExistingFile(filePath, fileType)
    print("Файл зарегистрирован: " .. filePath)
end)

concommand.Add("prp_modules_tree", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    print("=== Структура папок модулей ===")
    
    local gamemodePath = ""
    if GM and GM.FolderName then
        gamemodePath = GM.FolderName .. "/gamemode/modules/"
    elseif GAMEMODE and GAMEMODE.FolderName then
        gamemodePath = GAMEMODE.FolderName .. "/gamemode/modules/"
    else
        gamemodePath = "gamemodes/purpur-master/gamemode/modules/"
    end
    
    local function ShowTree(basePath, currentPath, indent)
        indent = indent or ""
        local items, dirs = file.Find(basePath .. currentPath .. "*", "LUA")
        
        if dirs then
            for _, dir in SortedPairs(dirs, true) do
                if dir ~= "." and dir ~= ".." then
                    print(indent .. "📁 " .. dir .. "/")
                    ShowTree(basePath, currentPath .. dir .. "/", indent .. "  ")
                end
            end
        end
        
        if items then
            for _, item in SortedPairs(items, true) do
                if item:match("%.lua$") then
                    local prefix = item:sub(1, 3)
                    local icon = "📄"
                    if prefix == "sh_" then
                        icon = "🔄"
                    elseif prefix == "sv_" then
                        icon = "🖥️"
                    elseif prefix == "cl_" then
                        icon = "💻"
                    end
                    print(indent .. icon .. " " .. item)
                end
            end
        end
    end
    
    ShowTree(gamemodePath, "")
    print("=== Конец структуры ===")
end)

concommand.Add("prp_test_system", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    
    print("=== Тестирование системы загрузки модулей ===")
    
    if not prp.ModuleLoader then
        print("❌ Система загрузки модулей не инициализирована!")
        return
    end
    
    print("✅ Система загрузки модулей инициализирована")
    
    local moduleCount = 0
    for _ in pairs(prp.ModuleLoader.LoadedModules) do
        moduleCount = moduleCount + 1
    end
    
    print("📊 Загружено модулей: " .. moduleCount)
    
    local fileCounts = {}
    local duplicates = {}
    
    for moduleID, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
        local key = moduleData.fullPath
        fileCounts[key] = (fileCounts[key] or 0) + 1
        if fileCounts[key] > 1 then
            duplicates[key] = fileCounts[key]
        end
    end
    
    if next(duplicates) then
        print("⚠️  Найдены дублированные файлы:")
        for filePath, count in pairs(duplicates) do
            print("   - " .. filePath .. " (загружен " .. count .. " раз)")
        end
        print("💡 Используйте команду prp_clean_duplicates для очистки")
    else
        print("✅ Дубликатов не найдено")
    end
    
    local baseModules = {"sh_util.lua", "sh_hook.lua", "sh_job.lua", "sh_player.lua"}
    for _, moduleName in ipairs(baseModules) do
        local found = false
        for _, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
            if moduleData.name == moduleName then
                found = true
                break
            end
        end
        if found then
            print("✅ " .. moduleName .. " загружен")
        else
            print("❌ " .. moduleName .. " НЕ загружен")
        end
    end
    
    local nestedModules = {
    }
    
    print("\n🔍 Проверка вложенных модулей:")
    for _, moduleName in ipairs(nestedModules) do
        local found = false
        for _, moduleData in pairs(prp.ModuleLoader.LoadedModules) do
            if moduleData.name == moduleName then
                found = true
                print("✅ " .. moduleName .. " загружен (путь: " .. moduleData.fullPath .. ")")
                break
            end
        end
        if not found then
            print("❌ " .. moduleName .. " НЕ загружен")
        end
    end
    
    if prp.Debug and prp.Debug.Fallback then
        local fallback = prp.Debug:Fallback()
        print("✅ Используется модуль загрузки: " .. fallback)
    else
        print("❌ Модуль загрузки не найден")
    end

    if prp.Economy and prp.Economy.Money then
        print("✅ Модуль экономики загружен")
        print("   - Форматирование денег: " .. prp.Economy.Money:Format(1000))
    else
        print("❌ Модуль экономики не найден")
    end
    
    if prp.Weapons and prp.Weapons.Guns and prp.Weapons.Guns.Pistols then
        print("✅ Модуль оружия загружен")
        print("   - Количество пистолетов: " .. table.Count(prp.Weapons.Guns.Pistols.List))
    else
        print("❌ Модуль оружия не найден")
    end
    
    print("=== Тестирование завершено ===")
end)

if prp and prp.Util and prp.Util.Log then
    prp.Util:Log("Universal Module Loader System initialized", "INFO")
end 
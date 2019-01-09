local DialogStack = require "utils.DialogStack"
local UserDefault = require "utils.UserDefault"
local MapConfig = require "config.MapConfig"
local TipCfg = require "config.TipConfig"
local DialogConfig = require "config.DialogConfig"

local stack = {}
local top = nil;
local battleFlage = false

--[[
local function Reset(name, script, arg)
    if #stack > 1 and script == "view/map_scene.lua" then
        --print("SceneCount->"..#stack)
        for i = 1,#stack-1 do
            table.remove(stack,1)
        end
        --print("SceneCount->"..#stack)
    end
end
--]]

local function ClearBattleToggleScene()
    battleFlage = false
end

local function GetBattleStatus()
    local _status = battleFlage
    return _status
end

local function Push(name, script, arg)
    top = {
        name = name,
        script = script,
        arg = arg,
        savedValues = {},
        dialogStack = DialogStack.SetInstance(),
    }

    table.insert(stack, top)
    --Reset(name, script, arg)
    return top.savedValues;
end

local function Replace(name, script, arg)
    table.remove(stack)

    top = {
        name = name,
        script = script,
        arg = arg,
        savedValues = {},
        dialogStack = DialogStack.SetInstance(),
    }

    table.insert(stack, top)
    -- Reset(name, script, arg)
    return top.savedValues;
end

local function Pop()
    table.remove(stack)
    top = stack[#stack];
end

local noFadeScene = {
    HeroShowScene1 = true,
}

local isLoading = false;
local nextLoadingInfo = nil;
local nextSceneInfo = {}

local function GetNextSceneInfo()
    return nextSceneInfo;
end

local function LoadSceneAndWait(name, fade, arg, callback,AccountLoginScene)
    if name ~= "battle" and battleFlage then
        showDlgError(nil, "战斗内无法进行该操作")
        return
    end

    nextSceneInfo.scene_name = name;

    if name == "battle" then
        battleFlage = true
        utils.SGKTools.SynchronousPlayStatus({5,{1,module.playerModule.GetSelfID(),"combat"}})
    end

    if isLoading then
        nextLoadingInfo = {name, fade, arg, callback, AccountLoginScene};
        return
    end

    isLoading = true;

    local useAnimate = false -- (name == "battle");
    local useFade = not (noFadeScene[name] or (top and noFadeScene[top.name]))

    local tips="";
    local tipCfgTab=TipCfg.GetTipsConfig();
    if next(tipCfgTab)~=nil then
        local tipsGid=math.random(1, #tipCfgTab)
        tips=TipCfg.GetTipsConfig(tipsGid)
    end
    if AccountLoginScene then
        DialogStack.PushPref("AccountLoginSceneFrame",{name = name,callback = function ()
            collectgarbage();
            -- SGK.ResourcesManager.UnloadUnusedAssets()
            callback();
            if not arg or not arg.guide then
                utils.EventManager.getInstance():dispatch("SCENE_LOADED", name);
            end
            isLoading = false;
            if nextLoadingInfo then LoadSceneAndWait(table.unpack(nextLoadingInfo)); nextLoadingInfo = nil; end
        end},UnityEngine.GameObject.FindWithTag("UITopRoot").gameObject)
    else
        utils.SGKTools.LockMapClick(true)
        SceneService:UnloadOnNextScene();
        SceneService:SwitchScene(name, useAnimate, useFade, tips,function()
            collectgarbage();
            -- SGK.ResourcesManager.UnloadUnusedAssets()
            if callback then
                callback();
            end
            if not arg or not arg.guide then
                utils.EventManager.getInstance():dispatch("SCENE_LOADED", name);
            end
            isLoading = false;
            utils.SGKTools.LockMapClick(false)

            if nextLoadingInfo then LoadSceneAndWait(table.unpack(nextLoadingInfo)); nextLoadingInfo = nil; end
        end);
    end
end

local scene_switch_with_fade = true;

local function PopScene(...)
    local _data = ...
    if top and top.controller and top.controller.deActive then
        if not top.controller.deActive() then
            return;
        end
    end

    if battleFlage then
        battleFlage = false
    end
    if #stack > 1 then
        local nextTop = stack[#stack - 1];
        if nextTop.arg then
            nextSceneInfo.map_id = nextTop.arg.mapid
        else
            nextSceneInfo.map_id = nil;
        end
        LoadSceneAndWait(nextTop.name, scene_switch_with_fade, top.arg, function()
            UserDefault.Save();
            if top then top.controller = nil end
            local _id = module.MapModule.GetiMapid()
            SGK.BackgroundMusicService.SetMapID(_id)
            SGK.BackgroundMusicService.SwitchMusic()
            --Pop();
            local controller = SGK.LuaLoader.Load(nextTop.script, top.arg)
            if controller then  controller.savedValues = top.savedValues;  end
            top.controller = controller;
            top.dialogStack = DialogStack.SetInstance(top.dialogStack);
            if _data and _data.func then
                _data.func()
            end
        end)
        Pop();
    else
        StartScene("main_scene");
    end
end
local Map_id = 0
local function MapId(id)
    if type(id) == "number" then
        Map_id = id
        local MapConfig = require "config.MapConfig"
        if MapConfig.GetMapConf(id) then
            return MapConfig.GetMapConf(id).map_id
        end
    elseif type(id) == "string" then
        return id
    end
    return Map_id
end
local function ControllerProfiler(controller, name)
    if UnityEngine.Application.isEditor and controller.Start then
        local Start = controller.Start;
        controller.Start = function(...)
            local profiler = require "perf.profiler"
            profiler.start();
            Start(...)
            print(name .. " Start cost " .. profiler.time() .. "ms\n" .. profiler.report('TOTAL'));
            profiler.stop();
        end
    end
    return controller
end
local function LoadSceneLua(name, arg,parObj)
    local savedValues = {}
    local luaBehaviour = parObj:AddComponent(typeof(SGK.LuaBehaviour));

    local scriptFileName = "view/" .. name .. ".lua";
    local controller = nil
        local script = SGK.FileUtils.LoadStringFromFile(scriptFileName);
        if script then
            local func = loadstring(script, scriptFileName);
            if func then
                controller = ControllerProfiler(func(), scriptFileName);
            end
        end
    if controller then
        luaBehaviour:LoadScript(scriptFileName, controller, arg);
    end
    return parObj
end

local function PushScene(name, script, arg)
    if not DialogConfig.CheckDialog(name) then
        return
    end
    assert(script ~= "view/map_scene.lua")
    nextSceneInfo.map_id = nil;
    LoadSceneAndWait(name, scene_switch_with_fade, arg, function()
        UserDefault.Save();
        if top then top.controller = nil end
        if name == "battle" and top and top.name == "battle" then
            Replace(name, script)
        else
            Push(name, script)
        end
        if script then
            local controller = SGK.LuaLoader.Load(script, arg);
            if controller then  controller.savedValues = top.savedValues;  end
            top.controller = controller;
        end
    end)
end

local function PushScene_coroutine(name, script, arg)
    local co = coroutine.running()
    nextSceneInfo.map_id = nil;
    LoadSceneAndWait(name, scene_switch_with_fade, arg, function()
        UserDefault.Save();
        if top then top.controller = nil end
        if name == "battle" and top.name == "battle" then
            Replace(name, script)
        else
            Push(name, script)
        end
        local controller = SGK.LuaLoader.Load(script, arg);
        if controller then controller.savedValues = top.savedValues;  end
        top.controller = controller;
        coroutine.resume(co)
    end)
    coroutine.yield()
end
local function ReplaceScene(name, script, arg)
    if not DialogConfig.CheckDialog(name) then
        return
    end
    assert(script ~= "view/map_scene.lua")
    nextSceneInfo.map_id = nil;
    LoadSceneAndWait(name, scene_switch_with_fade, arg, function()
        UserDefault.Save();
        if top then top.controller = nil end
        Replace(name, script, arg)
        local controller = SGK.LuaLoader.Load(script, arg);
        if controller then controller.savedValues = top.savedValues;  end
        top.controller = controller;
    end)
end

function StartScene (name, script, arg)
    stack = {}
    top = nil;
    PushScene(name, script, arg)
end

local savedValues = setmetatable({}, {__index=function(t, k)
    return top and top.savedValues[k]
end, __newindex = function(t,k,v)
    if top then
        top.savedValues[k] = v;
    end
end});

local params = setmetatable({}, {__index=function(t, k)
    return top and top.arg[k]
end});

local function Count()
    return #stack
end

local function GetTopStack()
    return stack[#stack]
end
local function GetStack()
    return stack
end

local function GetCurrentSceneName()
    if #stack > 0 then
        return stack[#stack].name;
    else
        return "nil"
    end
end

local function GetCurrentSceneID()
    return MapId()
end

local function EnterMap(_id, args,AccountLoginScene)
    local mapCfg, name;
    local id = tonumber(_id)
    if id == nil then
        name = _id;
        id = MapConfig.GetMapId(name)
        mapCfg = id and MapConfig.GetMapConf(id)
    else
        mapCfg = MapConfig.GetMapConf(id)
        if not mapCfg then
            ERROR_LOG('map with id', id, 'not eixst');
            return;
        end
        name = mapCfg.map_id;
    end
    if mapCfg and mapCfg.sceneback == 0 then
        stack = {}
        top = nil;
    end

    if name == nil then
        ERROR_LOG("map, no found", _id)
        return
    end
    DispatchEvent("LockMapClickCreate",true)
    -- TODO:
    args = args or {};
    args.mapid = args.mapid or id;
    args.mapType = mapCfg.map_type
    args.map_move_style = mapCfg.map_move_style
    local script = "view/map_scene.lua";
    --if _id == 9 then
        Push(name, script,args)
    --end
    nextSceneInfo.map_id = args.mapid;
    LoadSceneAndWait(name, scene_switch_with_fade, args, function()
        UserDefault.Save();
        SGK.BackgroundMusicService.SetMapID(_id)
        SGK.BackgroundMusicService.SwitchMusic()
        --  if _id ~= 9 then
        --     Push(name, script)
        --     local controller = SGK.LuaLoader.Load(script, args)
        --     if controller then controller.savedValues = top.savedValues;  end
        -- end
        if args and args.func then
            args.func()
            args.func = nil
        end
    end,AccountLoginScene)
end


return {
    Push = PushScene,
    Replace = ReplaceScene,
    Pop = PopScene,
    Start  = StartScene,
    EnterMap = EnterMap,

    StartLoading = StartLoading,
    savedValues = savedValues,
    PushCoroutine = PushScene_coroutine,

    Count = Count,
    GetStack = GetStack,
    GetTopStack = GetTopStack,
    CurrentSceneName  = GetCurrentSceneName,
    CurrentSceneID  = GetCurrentSceneID,
    MapId = MapId,
    LoadSceneLua = LoadSceneLua,
    ClearBattleToggleScene = ClearBattleToggleScene,
    GetBattleStatus = GetBattleStatus,

    GetNextSceneInfo = GetNextSceneInfo,
}

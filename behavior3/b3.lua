local class = require("behavior3.core.middleclass")
local const = require("behavior3.const")

-- Class Declaration
local B3 = class("B3")

-- Core
B3.BlackBoard = require("behavior3.core.blackboard")
B3.Tick = require("behavior3.core.tick")

-- Actions
B3.Error = require("behavior3.actions.error")
B3.Failer = require("behavior3.actions.failer")
B3.Runner = require("behavior3.actions.runner")
B3.Succeeder = require("behavior3.actions.succeeder")
B3.Wait = require("behavior3.actions.wait")

--Composites
B3.Sequence = require("behavior3.composites.sequence")
B3.Selector = require("behavior3.composites.selector")
B3.MemSequence = require("behavior3.composites.mem_sequence")
B3.MemSelector = require("behavior3.composites.mem_selector")
B3.WeightSelector = require("behavior3.composites.weight_selector")

--Decorators
B3.Inverter = require("behavior3.decorators.inverter")
B3.Limiter = require("behavior3.decorators.limiter")
B3.MaxTime = require("behavior3.decorators.max_time")
B3.Repeater = require("behavior3.decorators.repeater")
B3.RepeatUntilFailure = require("behavior3.decorators.repeat_until_failure")
B3.RepeatUntilSuccess = require("behavior3.decorators.repeat_until_success")

---@param data table Behavior Tree data
---@param customNodeList table Table contain custom node classes
---@param debug boolean Tick debug print
function B3:initialize(data, customNodeList, debug)
    self.title = "The behavior tree"
    self.description = "Default description"
    self.properties = {}
    self.root = nil

    self.debug = debug or nil

    self:load(data, customNodeList)
end

---@param data table Behavior Tree data table
---@param nodeList table Table contain custom node classes
function B3:load(data, nodeList)
    if type(data) ~= "table" then
        return false
    end

    nodeList = nodeList or {}

    self.id = data.id or uuid4.generate()
    self.title = data.title or self.title
    self.description = data.description or self.description

    local nodes = {}
    local node

    for id, nodeData in pairs(data.nodes) do
        local Cls = nodeList[nodeData.name] or B3[nodeData.name]
        assert(Cls, string.format("unkonw node name:%s", nodeData.name))
        node = Cls:new(nodeData)
        nodes[id] = node

    end

    for id, nodeData in pairs(data.nodes) do
        node = nodes[id]
        if node.category == const.COMPOSITE and nodeData.children then
            for i = 1, #nodeData.children do
                local cid = nodeData.children[i]
                node.children[i] = nodes[cid]
            end
        elseif node.category == const.DECORATOR and nodeData.child then
            node.child = nodes[nodeData.child]
            assert(node.child, "not have a child")
        end
    end

    self.root = nodes[data.root]
end

function B3:dump()
    local data = {}
    local customNames = {}

    data.title = self.title
    data.description = self.description
    data.properties = self.properties
    data.nodes = {}
    data.custom_nodes = {}

    if self.root then
        data.root = self.root.id
    else
        return data
    end

    local stack = {self.root}

    while #stack > 0 do
        local node = table.remove(stack, #stack)
        local nodeData = {}
        nodeData.id = node.id
        nodeData.name = node.name
        nodeData.title = node.title
        nodeData.description = node.description
        nodeData.properties = node.properties
        nodeData.parameters = node.parameters

        --verify custom node
        local proto
        if node.constructor then
            proto = node.constructor.prototype
        end
        local nodeName = (proto and proto.name) or node.name
        if not B3[nodeName] and not customNames[nodeName] then
            local subdata = {}
            subdata.name = nodeName
            subdata.title = (proto and proto.title) or node.title
            subdata.category = node.category
            customNames[nodeName] = true
            table.insert(data.custom_nodes, subdata)
        end

        --store children/child
        local category = node.category
        if category == const.COMPOSITE and node.children then
            local children = {}
            for i = 1, #node.children do
                table.insert(children, node.children[i].id)
                table.insert(stack, node.children[i])
            end
            nodeData.children = children
        elseif category == const.DECORATOR and node.child then
            table.insert(stack, node.child)
            nodeData.child = node.child.id
        end
        data.nodes[node.id] = nodeData
    end
    return data
end

function B3:tick(tick)
    assert(tick, "tick object is important for tick method")
    assert(tick.agent, "agent is important for tick method")
    assert(tick.worldBlackboard, "worldBlackboard is important for tick method")

    tick.debug = self.debug
    tick.tree = self

    --TICK NODE
    local state = self.root:execute(tick)
    local agentBlackboard = tick.agent
    local lastOpenNodes = agentBlackboard:get("openNodes", self.id)
    local currOpenNodes = tick.openNodes

    --does not close if it is still open in this tick
    local start = 1
    local lastOpenNodesNum = #lastOpenNodes
    for i = 1, math.min(lastOpenNodesNum, #currOpenNodes) do
        start = i + 1
        if lastOpenNodes[i] ~= currOpenNodes[i] then
            break
        end
    end

    --close the nodes
    if lastOpenNodesNum > 0 then
        for i = lastOpenNodesNum, start, -1 do
            lastOpenNodes[i]:close(tick)
        end
    end

    --populate blackboard
    agentBlackboard:set("openNodes", currOpenNodes, self.id)
    agentBlackboard:set("nodeCount", tick.nodeCount, self.id)

    return state
end

return B3


core = require("core")
rx = require("rx")
utils = require("utils")

import assignObject, Timer, namespace, Store from utils
import Subject, AsyncSubject, ReplaySubject from rx



MAX_INTERFACE = 5000

--Notes:
--NetworkInterface uses replay subject making it remember all network data
--this might cause memory issues for interfaces open for longer amounts of time



addedPlayers = 0

_Send = Send


-- only send data if there are other players in game
export Send = (...) ->
  if addedPlayers > 0
    _Send(...)

  
class NetPlayer
  new: (id, name, team) =>
    @id = id
    @name = name
    @team = team
    @handle = GetPlayerHandle(team)
    @handleSubject = Subject.create() --ReplaySubject.create()

  getHandle: () => @handle
  getName: () => @name
  getId: () => @id
  getTeam: () => @team
  setHandle: (h) =>
    @handle = h



class Socket
  new: (interface, notify) =>
    @interface = interface
    @connectSubject = Subject.create()
    @receiveSubject = Subject.create()
    @incomingBuffer = {}
    @incomingQueueSize = 0
    @queue = {}
    @_currentId = 1
    @alive =  true
    @closeWhenEmpty = false
    @interface\getMessages()\subscribe(@\receive, nil, @\close)
    if notify
      @interface\send("C")

  _getNextId: () =>
    @_currentId += 1
    return @_currentId

  send: (...) =>
    package = table.pack(...)
    if(#package < 1)
      error("Can not send empty packages")
    package._head = 0
    package._id = @_getNextId()
    package._sub = AsyncSubject.create()
    table.insert(@queue,package)
    return package._sub

  sendNext: () =>
    if @alive
      p = @queue[1]
      if p
        d = #p
        if p._head > 0
          d = p[p._head]
        @interface\send("P", p._head,p._id,d)
        p._head += 1
        if(p._head > #p)
          p._sub\onNext(p._id)
          p._sub\onCompleted()
          table.remove(@queue,1)
      elseif @closeWhenEmpty and @incomingQueueSize <= 0
        @close()
  -- when someone else connects 
  onConnect: () =>
    return @connectSubject

  receive: (f,tpe,t,id,...) =>
    if @alive
      @incomingBuffer[f] = @incomingBuffer[f] or {}
      buffer = @incomingBuffer[f]
      if tpe == "P"
        if t == 0
          size = ...
          --print("Incoming package of size",size)
          buffer[id] = [0 for i=1, size]
          @incomingQueueSize += 1
        elseif buffer[id] ~= nil
          buffer[id][t] = ...
          --print("Got fragment", t, #buffer[id], t >= #buffer[id])
          if t >= #buffer[id]
            @receiveSubject\onNext(unpack(buffer[id],1,#buffer[id]))
            buffer[id] = nil
            @incomingQueueSize -= 1
      elseif tpe == "C"
        @connectSubject\onNext(f)

  onReceive: () =>
    return @receiveSubject

  getInterface: () =>
    @interface

  isOpen: () =>
    @alive
  
  waitClose: () =>
    @closeWhenEmpty = true

  close: () =>
    @alive = false
    @receiveSubject\onCompleted()
    @connectSubject\onCompleted()
    @incomingBuffer = {}
    if @interface\isOpen()
      @interface\close()



class BroadcastSocket extends Socket
  new: (...) =>
    super(...)
    @onReceive()\subscribe(super\send)
    
  send: (...) =>
    super(...)
    @receiveSubject\onNext(...)

class NetworkInterface
  new: (interface_id, to) =>
    @id = interface_id
    @to = type(to) == "number" and {to} or assignObject({},to)
    @subject = ReplaySubject.create()
    @alive = true

  send: (...) =>
    if @alive
      for i, v in pairs(@to)
        Send(v, "N", @id, ...)
    else
      error("Trying to send something via a closed network interface")

  getMessages: () =>
    @subject

  receive: (...) =>
    if @alive
      @subject\onNext(...)

  close: () =>
    if @alive
      @subject\onCompleted()
      @alive = false
    else
      error("Interface has already closed")

  isOpen: () =>
    @alive

  getId: () =>
    @id

class NetworkInterfaceManager
  new: () =>
    @networkInterfaces = {}
    -- our machines id
    @machine_id = -1
    -- the next interface id
    @nextInterface_id = 0
    -- subject that fires once networking is ready
    @networkReadySubject = AsyncSubject.create()
    -- subject that fires when a new host is selected
    @hostMigrationSubject = Subject.create()
    @isHostMigrating = false
    @network_ready = false
    -- the sockets that are listening for connections
    @serverSockets = {}
    -- recycled interface ids
    @availableIDs = {}
    -- sockets that we request to listen to
    @requestSockets = {}
    @requestSocketsIds = {}
    @playerInterfaceMap = {}
    @nextRequestId = 0
    @hostPlayer = nil


    @allSockets = {}
    @playerCount = 0
    @players = {}
    @lastPlayer = {}


  getLocalPlayer: () =>
    if not @isNetworkReady
      error("Unknown! Network is not ready")
    return @localPlayer

  isNetworkReady: () =>
    return @network_ready

  onNetworkReady: () =>
    return @networkReadySubject

  onHostMigration: () =>
    return @hostMigrationSubject

  getInterfaceById: (id) =>
    @networkInterfaces[id]

  _getOrCreateInterface: (id, to) =>
    i = @getInterfaceById(id)
    if i == nil
      i = NetworkInterface(id, to)
      if @playerInterfaceMap[to] == nil
        @playerInterfaceMap[to] = {}
      @playerInterfaceMap[to][id] = true
      @networkInterfaces[id] = i
      i\getMessages()\subscribe(nil, nil, () ->
        @playerInterfaceMap[to][id] = nil
        @networkInterfaces[id] = nil
        @allSockets[id] = nil
      )
    return i

  _terminateInterface: (interface_id) =>
    Send(0, "X", interface_id)
    @allSockets[interface_id] = nil
    @networkInterfaces[interface_id] = nil
    table.insert(@availableIDs,id)

  
  -- cleans up all sockets and network interfaces after a player has left
  _cleanUpInterfaces: (player) =>


  createNewInterface: (to) =>
    id = nil
    if #@availableIDs <= 0
      @nextInterface_id = @nextInterface_id % (MAX_INTERFACE + 1)  + 1
      id = @nextInterface_id + @machine_id * MAX_INTERFACE
      i = @getInterfaceById(id)
      -- if interface exists and it is open, that means we've used up all our interfaces, time to recycle
      if (i and i\isOpen())
        id = nil
        for i, v in pairs(@networkInterfaces)
          if not v\isOpen()
            table.insert(@availableIDs,i)

    if id == nil and #@availableIDs > 0
      id = table.remove(@availableIDs)
    
    if id ~= nil
      @networkInterfaces[id] = NetworkInterface(id, to)
      @networkInterfaces[id]\getMessages()\subscribe(nil,nil,() ->
        @_terminateInterface(id)
      )
      return @networkInterfaces[id]
    else
      error("All network interfaces used up!")

  _getLeaf: (tbl,...) =>
    t = {...}
    leaf = nil
    curr = tbl
    for v in *t
      if curr[v] == nil
        curr[v] = {}
      leaf = curr[v]
      curr = leaf
    return leaf

 


  openSocket: (to, socket_type, ...) =>
    socket_type = socket_type or Socket
    if @network_ready
      leaf = @_getLeaf(@serverSockets,...)
      if leaf
        if leaf.__socket
          error("Can not have multiple sockets on one channel")
        i = @createNewInterface(to)
        leaf.__socket = socket_type(i)
        @allSockets[i\getId()] = leaf.__socket
        leaf.__socket\onReceive()\subscribe(nil,nil,() ->
          print("Leaf: socket closed")
          leaf.__socket = nil
        )
        return leaf.__socket
      else
        error("No channels provided")
    else
      error("Network is not ready")
  
  getRemoteSocket: (...) =>
    leaf = @_getLeaf(@requestSockets, ...)
    if leaf
      if leaf.__socketSubject == nil
        @nextRequestId += 1
        leaf.__socketSubject = AsyncSubject.create()
        t = Timer(1, -1)
        args = {...}
        @requestSocketsIds[@nextRequestId] = {
          sub: leaf.__socketSubject, 
          leaf: leaf,
          timer: t,
          subscription: t\onAlarm()\subscribe(() -> 
            Send(0, "R", @nextRequestId, unpack(args))
          )
        }
        t\start()
        Send(0, "R", @nextRequestId, ...)
      return leaf.__socketSubject
    else
      error("No channels provided")

  receive: (f, t, a, ...) =>
    -- network interface package
    if @localPlayer and @localPlayer.id == f
      return
      
    if t == "N"
      i = @_getOrCreateInterface(a, f)
      i\receive(f,...)
    elseif t == "X"
      i = @getInterfaceById(a)
      if i
        i\close()

    elseif t == "R"
      leaf = @_getLeaf(@serverSockets,...)
      if leaf and leaf.__socket
        Send(f, "C", a, leaf.__socket\getInterface()\getId())

    elseif t == "C"
      if @requestSocketsIds[a]
        interface_id = ...
        r = @requestSocketsIds[a]
        r.subscription\unsubscribe()
        r.timer = nil
        s = Socket(@_getOrCreateInterface(interface_id, f), true)
        s\onReceive()\subscribe(nil,nil,() ->
          r.leaf.__socketSubject = nil
        )
        @allSockets[interface_id] = s
        r.sub\onNext(s)
        r.sub\onCompleted()
        @requestSocketsIds[a] = nil

    elseif t == "I"
      if @machine_id == -1
        @machine_id = a
        @localPlayer = @players[@machine_id]
        if IsHosting()
          @hostPlayer = @localPlayer
    elseif t == "H"
      @hostPlayer = @players[f] or {id: f, name: "Unknown", team: 0}
      if @isHostMigrating
        @hostMigrationSubject\onNext(@hostPlayer)
        @isHostMigrating = false
    if @hostPlayer~=nil and @machine_id~=-1 and not @network_ready
      print("Network is now ready")
      @network_ready = true
      @networkReadySubject\onNext()
      @networkReadySubject\onCompleted()

  start: () =>
    if IsNetGame() and not @network_ready and @playerCount <= 1
      @machine_id = @lastPlayer.id
      @localPlayer = @lastPlayer
      @network_ready = true
      @hostPlayer = @localPlayer
      @networkReadySubject\onNext()
      @networkReadySubject\onCompleted()
    elseif not IsNetGame()
      @machine_id = 0
      @localPlayer = {name: "Player", team: 1, id: 0}
      @hostPlayer = @localPlayer
      @network_ready = true
      @networkReadySubject\onNext()
      @networkReadySubject\onCompleted()
   
  update: (dtime) =>
    for i, v in ipairs(@requestSocketsIds)
      v.timer\update(dtime)
    
    for i, v in pairs(@allSockets)
      v\sendNext()

    if @isHostMigrating and IsHosting()
      @hostPlayer = @localPlayer
      @isHostMigrating = false
      @hostMigrationSubject\onNext(@hostPlayer)
      Send(0, "H")

  addPlayer: (id, name, team) =>
    print("Player added!",id,name,team)
    addedPlayers += 1
    @playerInterfaceMap[id] = {}
    if IsHosting() then
      Send(id, "H")
    Send(id, "I", id)

  createPlayer: (id, name, team) =>
    @playerCount += 1
    @players[id] = {:id, :name, :team}
    @lastPlayer = @players[id]
    --table.insert(@players,{:id,:name,:team})

  deletePlayer: (id, name, team) =>
    
    addedPlayers -= 1
    for i, v in pairs(@playerInterfaceMap[id] or {}) do
      @_getOrCreateInterface(i)\close()
    
    if id == (@hostPlayer or {id: -1}).id
      @isHostMigrating = true
    @players[id] = nil



class SharedStore extends Store
  new: (initial_state, socket) =>
    super(initial_state)
    @socket = socket
    @internal_store = Store(initial_state)

    --@extUpdate =  --super\onStateUpdate()\merge()
    --@extKeyUp = --super\onKeyUpdate()\merge(@internal_store\onKeyUpdate())
    --@internal_store\onKeyUpdate()\subscribe((key, value) ->
    --  print("Internal store set", key, value)
    --)
    super\onKeyUpdate()\subscribe((...) ->
      @socket\send("SET", ...)
      @internal_store\set(...)
    )

    @socket\onReceive()\subscribe((what, ...) ->
      if what == "SET"
        @silentSet(...)
        @internal_store\set(...)
        
    )

    @socket\onConnect()\subscribe(() -> 
      s = @getState()
      for i, v in pairs(s)
        @socket\send("SET", i, v)
    )

  onStateUpdate: () =>
    @internal_store\onStateUpdate()

  onKeyUpdate: () =>
    @internal_store\onKeyUpdate()



namespace("net",Socket, NetworkInterface, NetworkInterfaceManager)

net = core\useModule(NetworkInterfaceManager)

return {
  :Socket,
  :BroadcastSocket,
  :NetworkInterface,
  :NetworkInterfaceManager,
  :net,
  :SharedStore
}
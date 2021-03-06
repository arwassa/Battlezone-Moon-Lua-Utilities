utils = require("utils")
Rx = require("rx")

Module = require("module")
import Subject from Rx


class Event
  new: (name,source,target,...) =>
    @name = name
    @source = source
    @target = target
    @args = table.pack(...)

  getArgs: () =>
    unpack(@args)

  getName: () =>
    @name

  getSource: () =>
    @source

  getTarget: () =>
    @target

class EventDispatcher
  new: () =>
    @subjects = {}
    @eventQueue = {}

  on: (event) =>
    if(not @subjects[event])
      @subjects[event] = Subject.create()
    return @subjects[event]

  dispatch: (event) =>
    if(@subjects[event.name])
      @subjects[event.name]\onNext(event)
  
  queueEvent: (event) =>
    table.insert(@eventQueue, event)
  
  dispatchQueue: () =>
    for i, event in ipairs(@eventQueue)
      @dispatch(event)

    @eventQueue = {}



class EventDispatcherModule extends Module
  new: (...) =>
    super(...)
    @dispatcher = EventDispatcher()

  getDispatcher: () =>
    @dispatcher

  start: () =>
    super\start()
    @dispatcher\dispatch(Event("START",nil,nil))

  addObject: (...) =>
    super\addObject(...)
    @dispatcher\dispatch(Event("ADD_OBJECT",nil,nil,...))

  createObject: (...) =>
    super\createObject(...)
    @dispatcher\dispatch(Event("CREATE_OBJECT",nil,nil,...))

  deleteObject: (...) =>
    super\deleteObject(...)
    @dispatcher\dispatch(Event("DELETE_OBJECT",nil,nil,...))

  addPlayer: (...) =>
    super\addPlayer(...)
    @dispatcher\dispatch(Event("ADD_PLAYER",nil,nil,...))

  createPlayer: (...) =>
    super\createPlayer(...)
    @dispatcher\dispatch(Event("CREATE_PLAYER",nil,nil,...))

  deletePlayer: (...) =>
    super\deletePlayer(...)
    @dispatcher\dispatch(Event("DELETE_PLAYER",nil,nil,...))

  gameKey: (...) =>
    super\gameKey(...)
    @dispatcher\dispatch(Event("GAME_KEY",nil,nil,...))

  update: (...) =>
    super\update(...)
    @dispatcher\dispatch(Event("UPDATE",nil,nil,...))

{
  :EventDispatcherModule,
  :EventDispatcher,
  :Event
}

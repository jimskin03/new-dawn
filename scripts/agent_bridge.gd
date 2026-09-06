extends Node
## Local file RPC. The visible game owns the only simulation; clients never edit saves.
const Sim = preload("res://scripts/simulation.gd")
const PROTOCOL = "new-dawn-agent/1"
const GAME_ACTIONS = ["build","assign","upgrade","expedition","research","fortify","repair"]
const UI_ACTIONS = ["pause","resume","speed","step","select","tab","depth","dismiss","save","load","new_game","screenshot","shutdown","state"]
var game: Control
var directory = ""
var session_id = ""
var active = false
var status_message = "starting"
var sequence = 0
var elapsed_since_publish = 0.0
var elapsed_since_poll = 0.0
var busy = false
var ledger: Dictionary = {}
var id_pattern = RegEx.new()
var last_action: Dictionary = {}

func start(owner_game: Control, path: String) -> String:
 game=owner_game;directory=path.replace("\\","/").simplify_path()
 if not directory.is_absolute_path():return _fail("Agent directory must be absolute.")
 for sub in ["","requests","responses","screenshots"]:
  if DirAccess.make_dir_recursive_absolute(directory.path_join(sub))!=OK:return _fail("Cannot write agent directory.")
 var old=_read_json(directory.path_join("state.json"))
 if old.get("running",false) and now_ms()-float(old.get("updated_at_ms",0))<5000:
  return _fail("Another game owns this agent directory. Use a separate --agent-dir.")
 session_id=Crypto.new().generate_random_bytes(16).hex_encode()
 id_pattern.compile("^[A-Za-z0-9_-]{1,80}$")
 active=true;status_message="connected";publish()
 print("AGENT_BRIDGE_READY "+directory+" session="+session_id)
 return ""

func _fail(message: String) -> String:
 status_message=message;active=false;return message

static func now_ms() -> int:
 return int(Time.get_unix_time_from_system()*1000)

func _read_json(path: String) -> Dictionary:
 if not FileAccess.file_exists(path):return {}
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()>1048576:return {}
 var parser=JSON.new()
 if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return {}
 return parser.data

func _write_json(path: String, value: Dictionary) -> bool:
 var temp=path+"."+session_id+".tmp"
 var file=FileAccess.open(temp,FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(value,"",true,true));file.close()
 return DirAccess.rename_absolute(temp,path)==OK

func _process(dt: float) -> void:
 if not active:return
 elapsed_since_poll+=dt;elapsed_since_publish+=dt
 if elapsed_since_poll>=.10:
  elapsed_since_poll=0
  var existing=_read_json(directory.path_join("state.json"))
  if not existing.is_empty() and existing.get("session_id")!=session_id:
   _fail("Agent directory was claimed by another game.");return
  if not busy:_poll_requests()
 if elapsed_since_publish>=.25:elapsed_since_publish=0;publish()

func _exit_tree() -> void:
 if active:
  var value=live_state();value.running=false
  _write_json(directory.path_join("state.json"),value)

func publish() -> Dictionary:
 sequence+=1
 var state=live_state()
 if not _write_json(directory.path_join("state.json"),state):status_message="State write failed"
 return state

func live_state() -> Dictionary:
 var model=game.sim
 var snapshot: Dictionary=model.snapshot()
 snapshot.erase("rng_state")
 var net: Dictionary=model.rates()
 var room_data: Array=[]
 for i in range(model.rooms.size()):
  var room: Dictionary=model.rooms[i].duplicate(true)
  room["id"]=i;room["chamber"]=i+1;room["floor"]=int(i/2)+1
  room["name"]="Empty chamber" if room.kind=="" else Sim.ROOM_TYPES[room.kind].name
  room["output_per_second"]=model.gross_output(i)
  room["upgrade_cost"]=model.upgrade_cost(i) if room.kind!="" and room.level<3 else null
  room_data.append(room)
 snapshot.rooms=room_data
 var depletion: Dictionary={}
 for key in model.stock:depletion[key]=model.stock[key]/-net[key] if net[key]<0 else null
 var blockers: Array=[]
 if game.speed==0:blockers.append("paused")
 if game.modal!="":blockers.append("modal:"+game.modal)
 if model.outcome!="":blockers.append("run_ended")
 return {"protocol":PROTOCOL,"session_id":session_id,"pid":OS.get_process_id(),"running":true,"sequence":sequence,"updated_at_ms":now_ms(),
  "simulation":snapshot,"day":model.day(),"rates":net,"capacity":model.capacity(),"idle_workers":model.idle_workers(),"scientists":model.scientist_count(),
  "defense":model.defense(),"objective":model.objective(),"depletion_seconds":depletion,
  "next_raid":{"in_seconds":model.raid_in,"threat":46+model.raids_survived*9,"projected_damage":maxi(3,46+model.raids_survived*9-model.defense())},
  "ui":{"visible":DisplayServer.get_name()!="headless","speed":game.speed,"advancing":blockers.is_empty(),"blocked_by":blockers,"selected_room":game.selected,"tab":game.tab,"depth":game.depth,"modal":game.modal,"logical_size":[1600,1000]},
  "available_actions":available_actions(),"last_action":last_action,"bridge":{"directory":directory,"status":status_message,"poll_seconds":.10,"publish_seconds":.25}}

func available_actions() -> Array:
 # Derive legality from the same simulation methods the GUI uses.
 var candidates: Array=[]
 for i in range(game.sim.rooms.size()):
  var room: Dictionary=game.sim.rooms[i]
  if room.kind=="":
   for kind in Sim.ROOM_TYPES:
    if kind!="command":candidates.append({"action":"build","args":{"room":i,"kind":kind},"cost":{"scrap":Sim.ROOM_TYPES[kind].cost}})
  else:
   candidates.append({"action":"assign","args":{"room":i,"delta":1}})
   candidates.append({"action":"assign","args":{"room":i,"delta":-1}})
   candidates.append({"action":"upgrade","args":{"room":i},"cost":{"scrap":game.sim.upgrade_cost(i)}})
 for route in ["depot","reservoir","outpost"]:candidates.append({"action":"expedition","args":{"route":route},"cost":{"food":12}})
 for key in Sim.RESEARCH:candidates.append({"action":"research","args":{"key":key},"cost":{"scrap":Sim.RESEARCH[key].cost}})
 candidates.append({"action":"fortify","args":{},"cost":{"energy":30}})
 candidates.append({"action":"repair","args":{},"cost":{"scrap":35}})
 var legal: Array=[]
 var trial=Sim.new();var initial: Dictionary=game.sim.snapshot()
 for candidate in candidates:
  if not trial.restore(initial):break
  if apply_model_action(trial,candidate.action,candidate.args)=="":legal.append(candidate)
 return legal

static func integer(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))

static func validate_action(action: String, args: Dictionary) -> String:
 var schema={"build":["room","kind"],"assign":["room","delta"],"upgrade":["room"],"expedition":["route"],"research":["key"],"fortify":[],"repair":[],"pause":[],"resume":[],"speed":["rate"],"step":["seconds"],"select":["room"],"tab":["name"],"depth":["value"],"dismiss":[],"save":[],"load":[],"new_game":["confirm"],"screenshot":[],"shutdown":[],"state":{}}
 if action not in schema:return "Unknown action: "+action
 for key in args:
  if key not in schema[action]:return "Unexpected argument: "+str(key)
 for key in schema[action]:
  if not args.has(key):return "Missing argument: "+key
 if args.has("room") and (not integer(args.room) or (args.room<0 and not (action=="select" and int(args.room)==-1)) or args.room>9):return "room must be an integer from 0 to 9."
 if action=="assign" and (not integer(args.delta) or int(args.delta) not in [-1,1]):return "delta must be -1 or 1."
 if action=="build" and (not args.kind is String or args.kind not in Sim.ROOM_TYPES or args.kind=="command"):return "Unknown buildable room type."
 if action=="expedition" and args.route not in ["depot","reservoir","outpost"]:return "Unknown expedition route."
 if action=="research" and args.key not in Sim.RESEARCH:return "Unknown research key."
 if action=="speed" and (not integer(args.rate) or int(args.rate) not in [0,1,2,4]):return "rate must be 0, 1, 2, or 4."
 if action=="step" and (not (args.seconds is int or args.seconds is float) or not is_finite(float(args.seconds)) or args.seconds<=0 or args.seconds>30):return "seconds must be greater than 0 and at most 30."
 if action=="tab" and args.name not in ["Shelter","Build","People","Research","Map"]:return "Unknown tab name."
 if action=="depth" and (not integer(args.value) or args.value<0 or args.value>2):return "depth value must be 0, 1, or 2."
 if action=="new_game" and args.confirm!=true:return "new_game requires confirm: true."
 return ""

static func apply_model_action(model: RefCounted, action: String, args: Dictionary) -> String:
 var error=validate_action(action,args)
 if error!="":return error
 match action:
  "build":return model.build_room(int(args.room),args.kind)
  "assign":return model.assign(int(args.room),int(args.delta))
  "upgrade":return model.upgrade_room(int(args.room))
  "expedition":return model.start_expedition(args.route)
  "research":return model.start_research(args.key)
  "fortify":return model.brace()
  "repair":return model.repair()
 return "Not a simulation action."

func _poll_requests() -> void:
 var files=DirAccess.get_files_at(directory.path_join("requests"));files.sort()
 var processed=0
 for file in files:
  if not file.ends_with(".json"):continue
  if processed>=8 or busy:break
  processed+=1
  var id=file.trim_suffix(".json")
  var path=directory.path_join("requests").path_join(file)
  if id_pattern.search(id)==null:continue
  var request=_read_json(path)
  if request.get("id")!=id:
   _finish({"id":id,"action":"","args":{},"session_id":""},"invalid_request","Invalid JSON or request id does not match filename.")
   DirAccess.remove_absolute(path);continue
  if ledger.has(id):
   # A retry receives the original result; an id is never executed twice.
   _write_json(directory.path_join("responses").path_join(file),ledger[id])
   DirAccess.remove_absolute(path);continue
  if request.get("session_id")!=session_id:
   _finish(request,"wrong_session","Read state.json and use its current session_id.")
   DirAccess.remove_absolute(path);continue
  if not request.get("action") is String or not request.get("args",{}) is Dictionary:
   _finish(request,"invalid_request","action must be a string and args an object.")
   DirAccess.remove_absolute(path);continue
  if ledger.size()>=10000:
   _finish(request,"session_limit","Start a new process to open a fresh command session.",false)
   DirAccess.remove_absolute(path);continue
  if request.has("expected_sequence") and request.expected_sequence!=sequence:
   _finish(request,"stale_state","The state sequence changed. Read fresh state before acting.")
   DirAccess.remove_absolute(path);continue
  var action: String=request.action;var args: Dictionary=request.get("args",{})
  var error=validate_action(action,args)
  if error!="":
   _finish(request,"invalid_action",error);DirAccess.remove_absolute(path);continue
  if action=="screenshot" and DisplayServer.get_name()!="headless":
   busy=true;_screenshot.call_deferred(request)
   DirAccess.remove_absolute(path);continue
  error=_execute(action,args)
  _finish(request,"ok" if error=="" else "rejected",error)
  DirAccess.remove_absolute(path)
  if action=="shutdown" and error=="":get_tree().quit();break

func _execute(action: String, args: Dictionary) -> String:
 if action in GAME_ACTIONS:
  var error=apply_model_action(game.sim,action,args)
  if error=="":
   if args.has("room"):
    game.select_room(int(args.room));game.depth=clampi(int(args.room/2)-2,0,2)
   elif action=="research":game.set_tab("Research")
   elif action=="expedition":game.set_tab("Map")
   game.notify_user("Agent: "+action)
  return error
 match action:
  "pause":game.speed=0
  "resume":
   if game.sim.outcome!="":return "The run has ended."
   game.modal="";game.speed=1
  "speed":game.speed=int(args.rate)
  "step":
   if game.speed!=0:return "Pause before stepping."
   if game.modal=="encounter":
    game.sim.resolve_encounter(1);game.modal=""
   if game.modal!="":return "Dismiss the modal before stepping."
   if game.sim.outcome!="":return "The run has ended."
   game.sim.tick(float(args.seconds));game.sync_outcome()
  "select":game.select_room(int(args.room));if int(args.room)>=0:game.depth=clampi(int(args.room/2)-2,0,2)
  "tab":game.set_tab(args.name)
  "depth":game.depth=int(args.value)
  "dismiss":
   if game.modal=="encounter":game.sim.resolve_encounter(1)
   game.modal=""
  "save":return game.save_game(false)
  "load":
   var error: String=game.load_game(false)
   if error=="":game.speed=0;game.modal="";game.sync_outcome()
   return error
  "new_game":game.new_game();game.speed=0
  "screenshot":return "Screenshots require the GUI renderer; this process is headless."
  "shutdown":
   var error: String=game.save_game(false)
   if error!="":return "Could not save before closing: "+error
  "state":pass
 game.queue_redraw()
 return ""

func _finish(request: Dictionary, code: String, message: String, remember: bool=true, extra: Dictionary={}) -> void:
 last_action={"id":request.id,"action":request.get("action",""),"ok":code=="ok","code":code,"message":message,"at_ms":now_ms()}
 game.queue_redraw()
 var response={"protocol":PROTOCOL,"session_id":session_id,"id":request.id,"ok":code=="ok","code":code,"error":message,"request":request,"result":extra,"state":publish()}
 if remember:ledger[request.id]=response
 if not _write_json(directory.path_join("responses").path_join(str(request.id)+".json"),response):status_message="Response write failed; retry the same request id."

func _screenshot(request: Dictionary) -> void:
 game.queue_redraw()
 await RenderingServer.frame_post_draw
 var path=directory.path_join("screenshots").path_join(str(request.id)+".png")
 var result=get_viewport().get_texture().get_image().save_png(path)
 _finish(request,"ok" if result==OK else "capture_failed","" if result==OK else "Screenshot could not be saved.",true,{"path":path,"frame":Engine.get_frames_drawn()})
 busy=false

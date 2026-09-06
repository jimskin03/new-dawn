extends RefCounted
## Deterministic, UI-independent shelter simulation. All time is in game seconds.

const DAY_LENGTH = 90.0
const MAX_LEVEL = 3
const ROOM_TYPES = {
 "command": {"name":"Command Center", "cost":0, "color":"76c9e2", "desc":"The heart of Shelter 07. Coordinates salvage and reinforces the entrance.", "output":"scrap", "rate":0.24},
 "power": {"name":"Power Generator", "cost":110, "color":"eeb85c", "desc":"Keeps the lights on. Staff it to generate energy for every room.", "output":"energy", "rate":0.90},
 "water": {"name":"Water Treatment", "cost":100, "color":"79bdec", "desc":"Filters groundwater into clean drinking water for your survivors.", "output":"water", "rate":0.48},
 "food": {"name":"Hydroponics", "cost":100, "color":"abd477", "desc":"Fresh greens beneath the wasteland. Produces food every second.", "output":"food", "rate":0.42},
 "dorm": {"name":"Sleeping Quarters", "cost":90, "color":"cfb69b", "desc":"A place to call home. Adds four beds per level; no workers needed.", "output":"", "rate":0.0},
 "lab": {"name":"Research Lab", "cost":140, "color":"93d9d0", "desc":"Unlocks research. Assign a scientist here to develop the rescue relay.", "output":"", "rate":0.0},
 "workshop": {"name":"Workshop", "cost":120, "color":"dbab79", "desc":"Turns recovered equipment into building materials and repair parts.", "output":"scrap", "rate":0.58},
 "security": {"name":"Security Room", "cost":135, "color":"ce9376", "desc":"Each assigned guard adds 18 defense per level against incoming raiders.", "output":"", "rate":0.0},
 "medbay": {"name":"Medical Bay", "cost":130, "color":"c0d9d9", "desc":"A staffed medical bay restores morale and slowly repairs shelter integrity.", "output":"", "rate":0.0}
}
const RESEARCH = {
 "efficiency":{"name":"Closed-loop systems", "cost":90, "time":28.0, "desc":"All resource production +25%."},
 "defense":{"name":"Reinforced bulkheads", "cost":100, "time":30.0, "desc":"Permanent +25 shelter defense."},
 "relay":{"name":"Long-range relay", "cost":160, "time":45.0, "desc":"Restore the rescue signal. Requires Closed-loop systems."}
}

var stock = {"energy":170.0,"food":145.0,"water":160.0,"scrap":320.0}
var rooms: Array = []
var survivors = 6
var integrity = 100.0
var morale = 88.0
var elapsed = 0.0
var raid_in = 115.0
var raids_survived = 0
var braced = false
var expedition: Dictionary = {}
var research: Dictionary = {}
var unlocked: Array = []
var log_entries: Array = []
var outcome = ""
var revision = 0
var rng = RandomNumberGenerator.new()
var last_day = 1

func _init() -> void:
 rng.seed = 7041
 for kind in ["command","power","water","food","dorm","","","","",""]:
  rooms.append({"kind":kind,"level":1,"workers":1 if kind in ["command","power","water","food"] else 0,"build_left":0.0,"build_total":0.0})
 record("Shelter 07 is online. Six survivors are counting on you.")

func record(message: String) -> void:
 log_entries.push_front({"day":day(),"text":message})
 if log_entries.size()>30:log_entries.resize(30)
 revision += 1

func day() -> int:
 return int(elapsed / DAY_LENGTH) + 1

func capacity() -> int:
 var beds = 4
 for r in rooms:
  if r.kind == "dorm" and r.build_left <= 0:beds += 4 * int(r.level)
 return beds

func idle_workers() -> int:
 var assigned = 2 if not expedition.is_empty() else 0
 for r in rooms:assigned += int(r.workers)
 return maxi(0,survivors-assigned)

func scientist_count() -> int:
 var count = 0
 for r in rooms:
  if r.kind == "lab" and r.build_left<=0:count += int(r.workers)
 return count

func has_room(kind: String) -> bool:
 for r in rooms:
  if r.kind == kind and r.build_left<=0:return true
 return false

func defense() -> int:
 var value = 15 + (25 if "defense" in unlocked else 0) + (45 if braced else 0)
 for r in rooms:
  if r.build_left<=0:
   if r.kind=="security":value += 18*int(r.workers)*int(r.level)
   if r.kind=="command":value += 8*int(r.workers)*int(r.level)
 return value

func max_stock(key: String) -> float:
 return 999.0 if key=="scrap" else 360.0

func gross_output(index: int) -> float:
 var r: Dictionary = rooms[index]
 if r.kind=="" or r.build_left>0:return 0.0
 var boost = 1.25 if "efficiency" in unlocked else 1.0
 var powered = 0.25 if stock.energy<=0 and r.kind!="power" else 1.0
 return float(ROOM_TYPES[r.kind].rate)*int(r.workers)*int(r.level)*boost*powered

func rates() -> Dictionary:
 var result = {"energy":0.0,"food":-survivors*.042,"water":-survivors*.052,"scrap":0.0}
 for i in range(rooms.size()):
  var r: Dictionary=rooms[i]
  if r.kind=="" or r.build_left>0:continue
  if r.kind!="power":result.energy -= .085 * int(r.level)
  var output: String=ROOM_TYPES[r.kind].output
  if output!="":result[output] += gross_output(i)
 return result

func assign(index: int, change: int) -> String:
 if outcome!="":return "This run has ended. Start a new shelter to continue."
 if index<0 or index>=rooms.size():return "Choose a room first."
 var r: Dictionary=rooms[index]
 if r.kind=="" or r.build_left>0:return "This room is not ready."
 if r.kind=="dorm":return "Sleeping quarters do not need workers."
 if change>0 and (idle_workers()==0 or r.workers>=3):return "No available survivors, or room is fully staffed."
 if change<0 and r.workers<=0:return "This room is already unstaffed."
 r.workers=clampi(int(r.workers)+signi(change),0,3);revision+=1
 return ""

func build_room(index: int, kind: String) -> String:
 if outcome!="":return "This run has ended."
 if index<0 or index>=rooms.size() or rooms[index].kind!="":return "Select an empty chamber."
 if kind not in ROOM_TYPES or kind=="command":return "That room cannot be built."
 var cost: int=ROOM_TYPES[kind].cost
 if stock.scrap<cost:return "Not enough scrap. Send a scavenging team or staff the command center."
 stock.scrap-=cost;rooms[index]={"kind":kind,"level":1,"workers":0,"build_left":14.0,"build_total":14.0}
 record("Construction started: "+ROOM_TYPES[kind].name+".")
 return ""

func upgrade_cost(index: int) -> int:
 return 65*int(rooms[index].level)

func upgrade_room(index: int) -> String:
 if outcome!="":return "This run has ended."
 if index<0 or index>=rooms.size():return "Choose a room first."
 var r: Dictionary=rooms[index]
 if r.kind=="" or r.build_left>0:return "Wait until construction finishes."
 if r.level>=MAX_LEVEL:return "This room is at maximum level."
 var cost=upgrade_cost(index)
 if stock.scrap<cost:return "Not enough scrap for this upgrade."
 stock.scrap-=cost;r.level+=1;record(ROOM_TYPES[r.kind].name+" upgraded to level "+str(r.level)+".")
 return ""

func start_expedition(route: String) -> String:
 if outcome!="":return "This run has ended."
 if not expedition.is_empty():return "A team is already outside."
 if idle_workers()<2:return "Free two survivors from their rooms first."
 if stock.food<12:return "An expedition needs 12 food."
 if route not in ["depot","reservoir","outpost"]:return "Unknown destination."
 stock.food-=12;expedition={"route":route,"left":32.0 if route!="outpost" else 46.0,"total":32.0 if route!="outpost" else 46.0}
 record("Two survivors left for the "+route+".")
 return ""

func start_research(key: String) -> String:
 if outcome!="":return "This run has ended."
 if key not in RESEARCH:return "Unknown research."
 if key in unlocked:return "Already researched."
 if not research.is_empty():return "Another research project is in progress."
 if scientist_count()==0:return "Build a research lab and assign a scientist."
 if key=="relay" and "efficiency" not in unlocked:return "Research Closed-loop systems first."
 if stock.scrap<RESEARCH[key].cost:return "Not enough scrap."
 stock.scrap-=RESEARCH[key].cost;research={"key":key,"left":RESEARCH[key].time,"total":RESEARCH[key].time}
 record("Research started: "+RESEARCH[key].name+".")
 return ""

func brace() -> String:
 if outcome!="":return "This run has ended."
 if braced:return "The shelter is already fortified for the next raid."
 if stock.energy<30:return "Fortifying needs 30 energy."
 stock.energy-=30;braced=true;record("Blast doors sealed. +45 defense for the next raid.")
 return ""

func repair() -> String:
 if outcome!="":return "This run has ended."
 if integrity>=100:return "The shelter is already fully repaired."
 if stock.scrap<35:return "Repairs need 35 scrap."
 stock.scrap-=35;integrity=minf(100,integrity+25);record("Maintenance crews restored 25 shelter integrity.")
 return ""

func tick(delta: float) -> void:
 if outcome!="" or delta<=0:return
 # Substeps preserve shortage/production behavior for fast-forward and tests.
 var remaining=delta
 while remaining>0.0001 and outcome=="":
  var dt=minf(remaining,.25);_step(dt);remaining-=dt

func _step(dt: float) -> void:
 elapsed+=dt
 var net=rates()
 for key in stock:stock[key]=clampf(float(stock[key])+float(net[key])*dt,0,max_stock(key))
 var shortage=stock.food<=0 or stock.water<=0
 morale=clampf(morale+(-.30 if shortage else .020)*dt,0,100)
 if shortage:integrity=maxf(0,integrity-.11*dt)
 if survivors>capacity():morale=maxf(0,morale-.05*dt)
 for r in rooms:
  if r.build_left>0:
   r.build_left=maxf(0,r.build_left-dt)
   if r.build_left==0:record(ROOM_TYPES[r.kind].name+" ready. Select it to assign workers.")
  if r.kind=="medbay" and r.build_left<=0 and r.workers>0 and stock.energy>0:
   integrity=minf(100,integrity+.07*r.workers*dt);morale=minf(100,morale+.08*r.workers*dt)
 if not expedition.is_empty():
  expedition.left-=dt
  if expedition.left<=0:
   var route: String=expedition.route
   var loot={"scrap":float(rng.randi_range(85,115)),"food":24.0} if route=="depot" else {"water":100.0,"food":42.0}
   if route=="outpost":
    loot={"scrap":70.0,"food":30.0}
    if survivors<capacity():survivors+=1;record("A survivor joined the shelter. Welcome home.")
    else:loot.scrap+=40;record("The outpost traded supplies. Build more beds to recruit survivors.")
   for key in loot:stock[key]=minf(max_stock(key),stock[key]+loot[key])
   expedition={};record("Scavenging team returned with supplies from the "+route+".")
 if not research.is_empty() and scientist_count()>0 and stock.energy>0:
  research.left-=dt*scientist_count()
  if research.left<=0:
   var key: String=research.key;unlocked.append(key);research={};record("Research complete: "+RESEARCH[key].name+".")
 raid_in-=dt
 if raid_in<=0:
  var threat=46+raids_survived*9
  var damage=maxi(3,threat-defense())
  integrity=maxf(0,integrity-damage);morale=maxf(0,morale-damage*.22)
  raids_survived+=1;braced=false;raid_in=110.0
  record("Raid repelled. Shelter took "+str(damage)+" damage. Repair before the next attack.")
 if day()!=last_day:
  last_day=day();record("Dawn "+str(day())+". Another day, another chance.")
 if integrity<=0 or morale<=0:
  outcome="defeat";record("Shelter 07 went dark. Your next shelter can learn from this one.")
 elif day()>=7 and "relay" in unlocked:
  outcome="victory";record("A voice on the radio. The rescue convoy received your signal.")

func objective() -> Dictionary:
 if not has_room("lab"):return {"title":"A signal of hope","desc":"Build a Research Lab in an empty chamber.","progress":0.12}
 if scientist_count()==0:return {"title":"A curious mind","desc":"Assign one survivor to the Research Lab.","progress":0.30}
 if "efficiency" not in unlocked:return {"title":"Make every drop count","desc":"Research Closed-loop systems.","progress":0.45}
 if "relay" not in unlocked:return {"title":"Reach beyond the canyon","desc":"Research the Long-range relay.","progress":0.65}
 return {"title":"Hold on until dawn","desc":"Keep Shelter 07 alive until day 7.","progress":minf(.99,float(day())/7)}

func snapshot() -> Dictionary:
 return {"version":1,"stock":stock.duplicate(true),"rooms":rooms.duplicate(true),"survivors":survivors,"integrity":integrity,"morale":morale,"elapsed":elapsed,"raid_in":raid_in,"raids_survived":raids_survived,"braced":braced,"expedition":expedition.duplicate(true),"research":research.duplicate(true),"unlocked":unlocked.duplicate(),"log":log_entries.duplicate(true),"outcome":outcome,"rng_state":str(rng.state)}

func restore(data: Dictionary) -> bool:
 # Validate everything before replacing live state; malformed saves cannot partly load.
 if data.get("version")!=1 or not data.get("stock") is Dictionary or not data.get("rooms") is Array:return false
 if data.rooms.size()!=10:return false
 for key in stock:
  if not (data.stock.get(key) is float or data.stock.get(key) is int):return false
  if not is_finite(float(data.stock[key])) or data.stock[key]<0 or data.stock[key]>max_stock(key):return false
 var worker_total=0
 for r in data.rooms:
  if not r is Dictionary:return false
  if r.get("kind", "?")!="" and r.get("kind") not in ROOM_TYPES:return false
  for key in ["level","workers","build_left","build_total"]:
   if not (r.get(key) is float or r.get(key) is int):return false
  if r.level<1 or r.level>3 or r.workers<0 or r.workers>3 or r.build_left<0 or r.build_left>14:return false
  worker_total+=int(r.workers)
 for key in ["survivors","integrity","morale","elapsed","raid_in","raids_survived"]:
  if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])):return false
 if data.survivors<1 or data.survivors>44 or data.integrity<0 or data.integrity>100 or data.morale<0 or data.morale>100 or data.elapsed<0:return false
 if not data.get("expedition") is Dictionary or not data.get("research") is Dictionary or not data.get("unlocked") is Array or not data.get("log") is Array:return false
 var ex: Dictionary=data.expedition
 if not ex.is_empty():
  if ex.get("route") not in ["depot","reservoir","outpost"] or not (ex.get("left") is float or ex.get("left") is int) or not (ex.get("total") is float or ex.get("total") is int):return false
  if ex.left<0 or ex.left>46 or ex.total<=0:return false
  worker_total+=2
 if worker_total>data.survivors:return false
 var re: Dictionary=data.research
 if not re.is_empty():
  if re.get("key") not in RESEARCH or not (re.get("left") is float or re.get("left") is int) or not (re.get("total") is float or re.get("total") is int):return false
  if re.left<0 or re.left>45 or re.total<=0:return false
 for key in data.unlocked:
  if key not in RESEARCH:return false
 for entry in data.log:
  if not entry is Dictionary or not entry.get("text") is String or not (entry.get("day") is int or entry.get("day") is float):return false
 if data.get("outcome", "") not in ["","victory","defeat"]:return false
 stock=data.stock.duplicate(true);rooms=data.rooms.duplicate(true);survivors=int(data.survivors)
 integrity=data.integrity;morale=data.morale;elapsed=data.elapsed;raid_in=data.raid_in;raids_survived=int(data.raids_survived)
 braced=bool(data.get("braced",false));expedition=ex.duplicate(true);research=re.duplicate(true);unlocked=data.unlocked.duplicate();log_entries=data.log.duplicate(true)
 outcome=data.get("outcome", "");last_day=day();rng.state=int(data.get("rng_state", "7041"));revision+=1
 return true

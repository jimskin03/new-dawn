extends RefCounted
## Deterministic, UI-independent shelter simulation. All time is in game seconds.

const DAY_LENGTH = 90.0
const MAX_LEVEL = 3
const ROOM_TYPES = {
	"command": {"name":"Command Center", "cost":0, "color":"76c9e2", "desc":"The heart of Shelter 07. Coordinates salvage and reinforces the entrance.", "output":"scrap", "rate":0.24, "stat":"cha"},
	"power": {"name":"Power Generator", "cost":110, "color":"eeb85c", "desc":"Keeps the lights on. Staff it to generate energy for every room.", "output":"energy", "rate":0.90, "stat":"str"},
	"water": {"name":"Water Treatment", "cost":100, "color":"79bdec", "desc":"Filters groundwater into clean drinking water for your survivors.", "output":"water", "rate":0.48, "stat":"int"},
	"food": {"name":"Hydroponics", "cost":100, "color":"abd477", "desc":"Fresh greens beneath the wasteland. Produces food every second.", "output":"food", "rate":0.42, "stat":"end"},
	"dorm": {"name":"Sleeping Quarters", "cost":90, "color":"cfb69b", "desc":"A place to call home. Adds four beds per level; no workers needed.", "output":"", "rate":0.0, "stat":""},
	"lab": {"name":"Research Lab", "cost":140, "color":"93d9d0", "desc":"Unlocks research. Assign a scientist here to develop the rescue relay.", "output":"", "rate":0.0, "stat":"int"},
	"workshop": {"name":"Workshop", "cost":120, "color":"dbab79", "desc":"Turns recovered equipment into building materials and repair parts.", "output":"scrap", "rate":0.58, "stat":"str"},
	"security": {"name":"Security Room", "cost":135, "color":"ce9376", "desc":"Each assigned guard adds 18 defense per level against incoming raiders.", "output":"", "rate":0.0, "stat":"agi"},
	"medbay": {"name":"Medical Bay", "cost":130, "color":"c0d9d9", "desc":"A staffed medical bay restores morale and slowly repairs shelter integrity.", "output":"", "rate":0.0, "stat":"int"}
}
const RESEARCH = {
	"efficiency":{"name":"Closed-loop systems", "cost":90, "time":28.0, "desc":"All resource production +25%."},
	"defense":{"name":"Reinforced bulkheads", "cost":100, "time":30.0, "desc":"Permanent +25 shelter defense."},
	"relay":{"name":"Long-range relay", "cost":160, "time":45.0, "desc":"Restore the rescue signal. Requires Closed-loop systems."}
}

const TRAITS = ["Engineer", "Workaholic", "Optimist", "Green Thumb", "Lucky", "Resilient", "Coward"]
const PERKS = {
	"fast_learner": {"name":"Fast Learner", "desc":"+30% XP gain from all tasks"},
	"engineer": {"name":"Master Engineer", "desc":"+25% Power Generator output"},
	"green_thumb": {"name":"Green Thumb", "desc":"+25% Food production rate"},
	"medic": {"name":"Field Medic", "desc":"+50% Medical healing speed"},
	"scavenger": {"name":"Veteran Scavenger", "desc":"+35% Loot from expeditions"},
	"tough": {"name":"Tough as Nails", "desc":"+40 Max HP and 25% damage resistance"}
}

var stock = {"energy":170.0,"food":145.0,"water":160.0,"scrap":320.0,"credits":50.0}
var rooms: Array = []
var survivors = 6
var characters: Array = []
var next_char_id = 7
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

# Extended Systems
var emergencies: Array = []
var emergency_timer = 45.0
var abilities = {
	"overclock": {"cd": 0.0, "max_cd": 35.0, "timer": 0.0, "room": -1},
	"heal": {"cd": 0.0, "max_cd": 45.0},
	"drone": {"cd": 0.0, "max_cd": 60.0},
	"lockdown": {"cd": 0.0, "max_cd": 40.0, "timer": 0.0, "room": -1}
}
var active_encounter: Dictionary = {}
var encounter_triggered = false
var missions: Array = []
var next_mission_id = 1

func _init() -> void:
	rng.seed = 7041
	for kind in ["command","power","water","food","dorm","","","","",""]:
		rooms.append({"kind":kind,"level":1,"workers":1 if kind in ["command","power","water","food"] else 0,"build_left":0.0,"build_total":0.0})
	_init_characters()
	_init_missions()
	record("Shelter 07 is online. Six survivors are counting on you.")

func _init_characters() -> void:
	characters = [
		{"id":1, "name":"A.Ira", "gender":"f", "str":3, "int":7, "agi":4, "cha":3, "end":4, "hp":100.0, "max_hp":100.0, "hunger":90.0, "energy":95.0, "morale":90.0, "xp":0, "level":1, "trait":"Engineer", "perks":[], "room":1, "state":"working", "speech":"", "speech_time":0.0, "pos_x":200.0},
		{"id":2, "name":"Eli", "gender":"m", "str":5, "int":4, "agi":3, "cha":6, "end":5, "hp":100.0, "max_hp":100.0, "hunger":85.0, "energy":88.0, "morale":85.0, "xp":0, "level":1, "trait":"Workaholic", "perks":[], "room":0, "state":"working", "speech":"", "speech_time":0.0, "pos_x":250.0},
		{"id":3, "name":"Jun", "gender":"m", "str":4, "int":6, "agi":3, "cha":4, "end":5, "hp":100.0, "max_hp":100.0, "hunger":90.0, "energy":90.0, "morale":88.0, "xp":0, "level":1, "trait":"Optimist", "perks":[], "room":2, "state":"working", "speech":"", "speech_time":0.0, "pos_x":220.0},
		{"id":4, "name":"Sana", "gender":"f", "str":3, "int":5, "agi":5, "cha":4, "end":4, "hp":100.0, "max_hp":100.0, "hunger":92.0, "energy":92.0, "morale":90.0, "xp":0, "level":1, "trait":"Green Thumb", "perks":[], "room":3, "state":"working", "speech":"", "speech_time":0.0, "pos_x":240.0},
		{"id":5, "name":"Mara", "gender":"f", "str":4, "int":3, "agi":7, "cha":3, "end":5, "hp":100.0, "max_hp":100.0, "hunger":95.0, "energy":95.0, "morale":85.0, "xp":0, "level":1, "trait":"Lucky", "perks":[], "room":-1, "state":"idle", "speech":"", "speech_time":0.0, "pos_x":300.0},
		{"id":6, "name":"Noah", "gender":"m", "str":6, "int":3, "agi":4, "cha":4, "end":7, "hp":100.0, "max_hp":100.0, "hunger":90.0, "energy":90.0, "morale":85.0, "xp":0, "level":1, "trait":"Resilient", "perks":[], "room":-1, "state":"idle", "speech":"", "speech_time":0.0, "pos_x":350.0}
	]
	sync_workers()

func _init_missions() -> void:
	missions = [
		{"id":"m_power", "title":"Grid Stability", "desc":"Produce 30 Energy", "type":"produce", "resource":"energy", "current":0.0, "target":30.0, "scrap":80, "credits":25, "xp":40, "claimed":false},
		{"id":"m_scout", "title":"Wasteland Survey", "desc":"Complete a Scavenging Expedition", "type":"expedition", "current":0.0, "target":1.0, "scrap":90, "credits":30, "xp":50, "claimed":false},
		{"id":"m_tech", "title":"Scientific Horizon", "desc":"Construct a Research Lab", "type":"build", "target_room":"lab", "current":0.0, "target":1.0, "scrap":100, "credits":35, "xp":60, "claimed":false}
	]

func sync_workers() -> void:
	for r in rooms:
		r.workers = 0
	for c in characters:
		if c.room >= 0 and c.room < rooms.size():
			rooms[c.room].workers += 1
	survivors = characters.size()

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
	return 999.0 if (key=="scrap" or key=="credits") else 360.0

func is_room_overclocked(index: int) -> bool:
	return abilities.overclock.timer > 0 and abilities.overclock.room == index

func has_room_emergency(index: int) -> bool:
	for em in emergencies:
		if em.room == index: return true
	return false

func gross_output(index: int) -> float:
	var r: Dictionary = rooms[index]
	if r.kind=="" or r.build_left>0:return 0.0
	if has_room_emergency(index):return 0.0
	var boost = 1.25 if "efficiency" in unlocked else 1.0
	var powered = 0.25 if stock.energy<=0 and r.kind!="power" else 1.0
	var base = float(ROOM_TYPES[r.kind].rate)*int(r.workers)*int(r.level)*boost*powered
	# Stat & Trait Bonuses from living characters assigned here
	var stat_mult = 1.0
	var target_stat = ROOM_TYPES[r.kind].get("stat", "")
	for c in characters:
		if c.room == index:
			if target_stat != "":
				var val = c.get(target_stat, 4)
				stat_mult += (val - 4) * 0.04
			if c.trait == "Engineer" and r.kind == "power":
				stat_mult += 0.20
			if "engineer" in c.perks and r.kind == "power":
				stat_mult += 0.25
			if c.trait == "Workaholic":
				stat_mult += 0.15
			if "green_thumb" in c.perks and r.kind == "food":
				stat_mult += 0.25
	if is_room_overclocked(index):
		stat_mult *= 2.0
	return base * maxf(0.5, stat_mult)

func rates() -> Dictionary:
	var result = {"energy":0.0,"food":-survivors*.042,"water":-survivors*.052,"scrap":0.0,"credits":0.0}
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
	if change > 0:
		var chosen = null
		var target_stat = ROOM_TYPES[r.kind].get("stat", "")
		for c in characters:
			if c.room == -1 and not c.get("on_expedition", false):
				if chosen == null or (target_stat != "" and c.get(target_stat, 0) > chosen.get(target_stat, 0)):
					chosen = c
		if chosen != null:
			chosen.room = index
			chosen.state = "working"
			chosen.speech = "Reporting to " + ROOM_TYPES[r.kind].name + "!"
			chosen.speech_time = 3.0
	elif change < 0:
		for c in characters:
			if c.room == index:
				c.room = -1
				c.state = "idle"
				c.speech = "Taking a breather."
				c.speech_time = 3.0
				break
	sync_workers()
	revision += 1
	return ""

func assign_character(char_id: int, target_room: int) -> String:
	if outcome!="":return "This run has ended."
	var char_obj = null
	for c in characters:
		if c.id == char_id:
			char_obj = c; break
	if char_obj == null: return "Character not found."
	if char_obj.get("on_expedition", false): return "Character is currently outside on expedition."
	if target_room == -1:
		char_obj.room = -1
		char_obj.state = "idle"
		sync_workers()
		revision += 1
		return ""
	if target_room < 0 or target_room >= rooms.size(): return "Invalid room."
	var r = rooms[target_room]
	if r.kind == "" or r.build_left > 0: return "This room is not ready."
	if r.kind == "dorm": return "Sleeping quarters do not need workers."
	if char_obj.room != target_room and r.workers >= 3: return "Room is fully staffed."
	char_obj.room = target_room
	char_obj.state = "working"
	char_obj.speech = "On my way to " + ROOM_TYPES[r.kind].name + "."
	char_obj.speech_time = 3.5
	sync_workers()
	revision += 1
	record(char_obj.name + " assigned to " + ROOM_TYPES[r.kind].name + ".")
	return ""

func build_room(index: int, kind: String) -> String:
	if outcome!="":return "This run has ended."
	if index<0 or index>=rooms.size() or rooms[index].kind!="":return "Select an empty chamber."
	if kind not in ROOM_TYPES or kind=="command":return "That room cannot be built."
	var cost: int=ROOM_TYPES[kind].cost
	if stock.scrap<cost:return "Not enough scrap. Send a scavenging team or staff the command center."
	stock.scrap-=cost;rooms[index]={"kind":kind,"level":1,"workers":0,"build_left":14.0,"build_total":14.0}
	record("Construction started: "+ROOM_TYPES[kind].name+".")
	_check_mission("build", 1.0, kind)
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
	_check_mission("upgrade", 1.0, r.kind)
	return ""

func start_expedition(route: String) -> String:
	if outcome!="":return "This run has ended."
	if not expedition.is_empty():return "A team is already outside."
	if idle_workers()<2:return "Free two survivors from their rooms first."
	if stock.food<12:return "An expedition needs 12 food."
	if route not in ["depot","reservoir","outpost"]:return "Unknown destination."
	var count = 0
	for c in characters:
		if c.room == -1 and not c.get("on_expedition", false):
			c["on_expedition"] = true
			c.state = "expedition"
			c.speech = "Heading out to the " + route + "!"
			c.speech_time = 4.0
			count += 1
			if count == 2: break
	stock.food-=12;expedition={"route":route,"left":32.0 if route!="outpost" else 46.0,"total":32.0 if route!="outpost" else 46.0}
	encounter_triggered = false
	active_encounter = {}
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

func use_ability(name: String, target_room: int = -1) -> String:
	if outcome!="":return "This run has ended."
	if name not in abilities:return "Unknown ability."
	var ab = abilities[name]
	if ab.cd > 0:return "Ability is recharging (%ds remaining)." % ceili(ab.cd)
	match name:
		"overclock":
			if target_room < 0 or target_room >= rooms.size() or rooms[target_room].kind == "":
				return "Select an active room to overclock."
			if stock.energy < 20:return "Overclock requires 20 energy."
			stock.energy -= 20
			ab.timer = 15.0
			ab.room = target_room
			ab.cd = ab.max_cd
			record("OVERCLOCK ACTIVATED: " + ROOM_TYPES[rooms[target_room].kind].name + " running at 200% for 15s!")
		"heal":
			if stock.energy < 15:return "Emergency heal requires 15 energy."
			stock.energy -= 15
			ab.cd = ab.max_cd
			for c in characters:
				if (target_room == -1 and c.room == -1) or c.room == target_room:
					c.hp = minf(c.max_hp, c.hp + 40.0)
					c.speech = "Emergency meds received! Feeling better."
					c.speech_time = 3.0
			record("Emergency medical stimulus administered.")
		"drone":
			if stock.energy < 20:return "Deploying drone requires 20 energy."
			stock.energy -= 20
			ab.cd = ab.max_cd
			var scrap_gain = 35.0
			var food_gain = 25.0
			var cred_gain = 15.0
			stock.scrap = minf(max_stock("scrap"), stock.scrap + scrap_gain)
			stock.food = minf(max_stock("food"), stock.food + food_gain)
			stock.credits = minf(max_stock("credits"), stock.credits + cred_gain)
			record("Scout drone returned with 35 scrap, 25 food, and 15 credits.")
		"lockdown":
			if target_room < 0 or target_room >= rooms.size():return "Select a room to lockdown."
			ab.cd = ab.max_cd
			ab.timer = 10.0
			ab.room = target_room
			for i in range(emergencies.size()-1, -1, -1):
				if emergencies[i].room == target_room:
					emergencies.remove_at(i)
			record("BLAST LOCKDOWN engaged on chamber %d. Emergencies contained." % (target_room + 1))
	revision += 1
	return ""

func suppress_emergency(room_index: int) -> String:
	if outcome!="":return "This run has ended."
	for i in range(emergencies.size()-1, -1, -1):
		if emergencies[i].room == room_index:
			emergencies.remove_at(i)
			for c in characters:
				if c.room == room_index:
					gain_character_xp(c, 30)
			record("Emergency in " + ROOM_TYPES[rooms[room_index].kind].name + " suppressed successfully!")
			revision += 1
			return ""
	return "No active emergency in this chamber."

func trigger_emergency(kind: String = "") -> void:
	if rooms.size() == 0: return
	var valid_rooms = []
	for i in range(rooms.size()):
		if rooms[i].kind != "" and rooms[i].build_left <= 0:
			valid_rooms.append(i)
	if valid_rooms.size() == 0: return
	var room_idx = valid_rooms[rng.randi_range(0, valid_rooms.size() - 1)]
	for em in emergencies:
		if em.room == room_idx: return
	var kinds = ["fire", "malfunction"]
	var selected_kind = kind if kind != "" else kinds[rng.randi_range(0, kinds.size() - 1)]
	emergencies.append({"kind": selected_kind, "room": room_idx, "timer": 25.0})
	record("CRITICAL: " + selected_kind.to_upper() + " detected in " + ROOM_TYPES[rooms[room_idx].kind].name + "!")
	for c in characters:
		if c.room == room_idx:
			c.speech = "Emergency! The room is failing!"
			c.speech_time = 4.0
	revision += 1

func trigger_exploration_encounter() -> void:
	encounter_triggered = true
	var encounters = [
		{
			"title": "Abandoned Research Bunker",
			"desc": "The scout team reached an intact pre-war vault door with a coded keypad.",
			"opt1": "Hack security terminal (INT)",
			"opt2": "Pry open with heavy tools (STR)"
		},
		{
			"title": "Desert Trader Caravan",
			"desc": "A roaming scavenger caravan signals peacefully from the canyon ridge.",
			"opt1": "Trade 15 food for 45 Scrap & 20 Credits",
			"opt2": "Offer shelter to a skilled wanderer"
		},
		{
			"title": "Contaminated Silo",
			"desc": "High radiation readings detect pristine industrial power cells within.",
			"opt1": "Rush in for quick salvage (Risk HP)",
			"opt2": "Safely gather perimeter scrap"
		}
	]
	active_encounter = encounters[rng.randi_range(0, encounters.size() - 1)]
	active_encounter["pending"] = true
	record("WASTELAND ENCOUNTER: " + active_encounter.title)

func resolve_encounter(choice: int) -> String:
	if active_encounter.is_empty() or not active_encounter.get("pending", false):
		return "No pending encounter."
	active_encounter["pending"] = false
	match active_encounter.title:
		"Abandoned Research Bunker":
			if choice == 1:
				stock.credits = minf(max_stock("credits"), stock.credits + 45)
				stock.scrap = minf(max_stock("scrap"), stock.scrap + 60)
				record("Terminal hacked! Discovered pre-war credits and valuable scrap.")
			else:
				stock.scrap = minf(max_stock("scrap"), stock.scrap + 85)
				record("Vault door forced! Recovered heavy steel and machine parts.")
		"Desert Trader Caravan":
			if choice == 1:
				stock.food = maxf(0, stock.food - 15)
				stock.scrap = minf(max_stock("scrap"), stock.scrap + 45)
				stock.credits = minf(max_stock("credits"), stock.credits + 20)
				record("Favorable trade completed with the caravan.")
			else:
				if survivors < capacity():
					add_survivor("Recruit", "Optimist")
					record("A wanderer joined Shelter 07 from the caravan!")
				else:
					stock.scrap = minf(max_stock("scrap"), stock.scrap + 60)
					record("Shelter was full. Caravan gifted 60 scrap as parting thanks.")
		"Contaminated Silo":
			if choice == 1:
				stock.energy = minf(max_stock("energy"), stock.energy + 60)
				stock.scrap = minf(max_stock("scrap"), stock.scrap + 50)
				for c in characters:
					if c.get("on_expedition", false):
						c.hp = maxf(10.0, c.hp - 25.0)
				record("Recovered charged power cells, but explorers suffered radiation burns.")
			else:
				stock.scrap = minf(max_stock("scrap"), stock.scrap + 35)
				record("Safely scavenged outer perimeter.")
	active_encounter = {}
	revision += 1
	return ""

func add_survivor(name_prefix: String = "Survivor", forced_trait: String = "") -> void:
	var names = ["Mara","Eli","Jun","Sana","Noah","Iris","Ari","Luca","Rae","Finn","Kael","Vera","Cole","Nomi"]
	var name_choice = names[(next_char_id - 1) % names.size()]
	var trait_choice = forced_trait if forced_trait != "" else TRAITS[rng.randi_range(0, TRAITS.size() - 1)]
	var new_c = {
		"id": next_char_id,
		"name": name_choice,
		"gender": "f" if (next_char_id % 2 == 1) else "m",
		"str": rng.randi_range(3, 7),
		"int": rng.randi_range(3, 7),
		"agi": rng.randi_range(3, 7),
		"cha": rng.randi_range(3, 7),
		"end": rng.randi_range(3, 7),
		"hp": 100.0,
		"max_hp": 100.0,
		"hunger": 85.0,
		"energy": 90.0,
		"morale": 90.0,
		"xp": 0,
		"level": 1,
		"trait": trait_choice,
		"perks": [],
		"room": -1,
		"state": "idle",
		"speech": "Glad to find Shelter 07.",
		"speech_time": 4.0,
		"pos_x": 300.0
	}
	next_char_id += 1
	characters.append(new_c)
	sync_workers()

func gain_character_xp(c: Dictionary, amount: int) -> void:
	var mult = 1.30 if "fast_learner" in c.perks else 1.0
	c.xp += int(amount * mult)
	var req = c.level * 80
	if c.xp >= req:
		c.level += 1
		c.xp -= req
		c.speech = "Level Up! Feeling stronger."
		c.speech_time = 4.0
		var stats = ["str", "int", "agi", "cha", "end"]
		var chosen_stat = stats[rng.randi_range(0, stats.size() - 1)]
		c[chosen_stat] = mini(10, c.get(chosen_stat, 4) + 1)
		record(c.name + " reached Level " + str(c.level) + "! " + chosen_stat.to_upper() + " increased.")

func choose_perk(char_id: int, perk_id: String) -> String:
	if perk_id not in PERKS: return "Unknown perk."
	for c in characters:
		if c.id == char_id:
			if perk_id in c.perks: return "Character already has this perk."
			c.perks.append(perk_id)
			record(c.name + " gained perk: " + PERKS[perk_id].name + "!")
			revision += 1
			return ""
	return "Character not found."

func _check_mission(type: String, amount: float, extra: String = "") -> void:
	for m in missions:
		if m.claimed: continue
		if m.type == type:
			if type == "produce" and extra == m.get("resource", ""):
				m.current = minf(m.target, m.current + amount)
			elif type == "build" and (extra == m.get("target_room", "") or m.get("target_room", "") == ""):
				m.current = minf(m.target, m.current + amount)
			elif type == "upgrade" and (extra == m.get("target_room", "") or m.get("target_room", "") == ""):
				m.current = minf(m.target, m.current + amount)
			elif type == "expedition":
				m.current = minf(m.target, m.current + amount)

func claim_mission(mission_id: String) -> String:
	for i in range(missions.size()):
		var m = missions[i]
		if m.id == mission_id:
			if m.current < m.target: return "Mission objective not yet completed."
			if m.claimed: return "Already claimed."
			m.claimed = true
			stock.scrap = minf(max_stock("scrap"), stock.scrap + m.scrap)
			stock.credits = minf(max_stock("credits"), stock.credits + m.credits)
			for c in characters:
				gain_character_xp(c, m.xp)
			record("Objective Complete: " + m.title + "! (+" + str(m.scrap) + " scrap, +" + str(m.credits) + " credits)")
			_spawn_next_mission()
			revision += 1
			return ""
	return "Mission not found."

func _spawn_next_mission() -> void:
	var templates = [
		{"id":"m_power_" + str(next_mission_id), "title":"Overdrive", "desc":"Generate 40 Energy", "type":"produce", "resource":"energy", "current":0.0, "target":40.0, "scrap":80, "credits":30, "xp":40, "claimed":false},
		{"id":"m_water_" + str(next_mission_id), "title":"Fresh Water Source", "desc":"Produce 35 Water", "type":"produce", "resource":"water", "current":0.0, "target":35.0, "scrap":75, "credits":25, "xp":40, "claimed":false},
		{"id":"m_food_" + str(next_mission_id), "title":"Abundant Harvest", "desc":"Produce 35 Food", "type":"produce", "resource":"food", "current":0.0, "target":35.0, "scrap":75, "credits":25, "xp":40, "claimed":false},
		{"id":"m_up_" + str(next_mission_id), "title":"Shelter Refit", "desc":"Upgrade any room to next tier", "type":"upgrade", "current":0.0, "target":1.0, "scrap":90, "credits":35, "xp":50, "claimed":false},
		{"id":"m_exp_" + str(next_mission_id), "title":"Wasteland Expedition", "desc":"Complete a Scavenging Expedition", "type":"expedition", "current":0.0, "target":1.0, "scrap":85, "credits":40, "xp":50, "claimed":false}
	]
	next_mission_id += 1
	var new_m = templates[rng.randi_range(0, templates.size() - 1)]
	missions.append(new_m)
	for i in range(missions.size()-1, -1, -1):
		if missions[i].claimed:
			missions.remove_at(i)
			break

func tick(delta: float) -> void:
	if outcome!="" or delta<=0:return
	var remaining=delta
	while remaining>0.0001 and outcome=="":
		var dt=minf(remaining,.25);_step(dt);remaining-=dt

func _step(dt: float) -> void:
	elapsed+=dt
	var net=rates()
	for key in ["energy","food","water","scrap","credits"]:
		if key in net:
			var prev_val = stock[key]
			stock[key]=clampf(float(stock[key])+float(net[key])*dt,0,max_stock(key))
			if net[key] > 0:
				_check_mission("produce", (stock[key] - prev_val), key)
	var shortage=stock.food<=0 or stock.water<=0
	morale=clampf(morale+(-.30 if shortage else .020)*dt,0,100)
	if shortage:integrity=maxf(0,integrity-.11*dt)
	if survivors>capacity():morale=maxf(0,morale-.05*dt)
	
	# Character Needs Decay & Speech Ticks
	for c in characters:
		if c.speech_time > 0:
			c.speech_time = maxf(0, c.speech_time - dt)
			if c.speech_time == 0: c.speech = ""
		c.hunger = maxf(0, c.hunger - dt * 0.05)
		if c.state == "working":
			c.energy = maxf(0, c.energy - dt * 0.07)
			if int(elapsed) % 6 == 0 and dt >= 0.2:
				gain_character_xp(c, 1)
		elif c.state == "idle":
			c.energy = minf(100, c.energy + dt * 0.08)
		if c.room >= 0 and c.room < rooms.size() and rooms[c.room].kind == "dorm":
			c.energy = minf(100, c.energy + dt * 0.25)
			c.morale = minf(100, c.morale + dt * 0.10)
		if shortage:
			c.hp = maxf(0, c.hp - dt * 0.15)
			c.morale = maxf(0, c.morale - dt * 0.20)
		else:
			c.hp = minf(c.max_hp, c.hp + dt * 0.02)
			
	# Cooldowns on Abilities
	for ab_name in abilities:
		var ab = abilities[ab_name]
		if ab.cd > 0: ab.cd = maxf(0, ab.cd - dt)
		if ab.get("timer", 0.0) > 0: ab.timer = maxf(0, ab.timer - dt)

	# Emergency Tick & Auto-suppression by workers in room
	emergency_timer -= dt
	if emergency_timer <= 0:
		emergency_timer = rng.randf_range(35.0, 60.0)
		if rng.randf() < 0.65:
			trigger_emergency()

	for i in range(emergencies.size()-1, -1, -1):
		var em = emergencies[i]
		var r_idx = em.room
		var workers_in_room = 0
		for c in characters:
			if c.room == r_idx: workers_in_room += 1
		if workers_in_room > 0:
			em.timer -= dt * (1.0 + workers_in_room * 0.75)
			if em.timer <= 0:
				record(em.kind.capitalize() + " in " + ROOM_TYPES[rooms[r_idx].kind].name + " extinguished by workers!")
				for c in characters:
					if c.room == r_idx: gain_character_xp(c, 25)
				emergencies.remove_at(i)
				continue
		else:
			integrity = maxf(0, integrity - 0.45 * dt)
			em.timer -= dt * 0.2
			if em.timer <= 0:
				emergencies.remove_at(i)
				continue

	for r in rooms:
		if r.build_left>0:
			r.build_left=maxf(0,r.build_left-dt)
			if r.build_left==0:record(ROOM_TYPES[r.kind].name+" ready. Select it to assign workers.")
		if r.kind=="medbay" and r.build_left<=0 and r.workers>0 and stock.energy>0:
			integrity=minf(100,integrity+.07*r.workers*dt);morale=minf(100,morale+.08*r.workers*dt)
			for c in characters:
				c.hp = minf(c.max_hp, c.hp + 0.15 * r.workers * dt)
	if not expedition.is_empty():
		expedition.left-=dt
		if not encounter_triggered and expedition.left <= expedition.total * 0.5:
			trigger_exploration_encounter()
		if expedition.left<=0:
			var route: String=expedition.route
			var loot={"scrap":float(rng.randi_range(85,115)),"food":24.0,"credits":float(rng.randi_range(20,40))} if route=="depot" else {"water":100.0,"food":42.0,"credits":25.0}
			if route=="outpost":
				loot={"scrap":70.0,"food":30.0,"credits":35.0}
				if survivors<capacity():
					add_survivor("Scout", "Lucky")
					record("A survivor joined the shelter. Welcome home.")
				else:
					loot.scrap+=40;record("The outpost traded supplies. Build more beds to recruit survivors.")
			for c in characters:
				if c.get("on_expedition", false):
					c["on_expedition"] = false
					c.state = "idle"
					gain_character_xp(c, 40)
					if "scavenger" in c.perks:
						loot.scrap *= 1.35
						loot.credits *= 1.35
			for key in loot:stock[key]=minf(max_stock(key),stock[key]+loot[key])
			expedition={};active_encounter={};record("Scavenging team returned with supplies from the "+route+".")
			_check_mission("expedition", 1.0)
	if not research.is_empty() and scientist_count()>0 and stock.energy>0:
		var sci_boost = 0.0
		for c in characters:
			if c.room >= 0 and c.room < rooms.size() and rooms[c.room].kind == "lab":
				sci_boost += (c.int - 3) * 0.05
		var mult = maxf(1.0, 1.0 + sci_boost)
		research.left-=dt*scientist_count()*mult
		if research.left<=0:
			var key: String=research.key;unlocked.append(key);research={};record("Research complete: "+RESEARCH[key].name+".")
	raid_in-=dt
	if raid_in<=0:
		var threat=46+raids_survived*9
		var damage=maxi(3,threat-defense())
		integrity=maxf(0,integrity-damage);morale=maxf(0,morale-damage*.22)
		raids_survived+=1;braced=false;raid_in=110.0
		record("Raid repelled. Shelter took "+str(damage)+" damage. Repair before the next attack.")
		for c in characters:
			if c.room >= 0 and c.room < rooms.size() and rooms[c.room].kind == "security":
				gain_character_xp(c, 35)
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
	return {
		"version":1,
		"stock":stock.duplicate(true),
		"rooms":rooms.duplicate(true),
		"survivors":survivors,
		"characters":characters.duplicate(true),
		"next_char_id":next_char_id,
		"integrity":integrity,
		"morale":morale,
		"elapsed":elapsed,
		"raid_in":raid_in,
		"raids_survived":raids_survived,
		"braced":braced,
		"expedition":expedition.duplicate(true),
		"research":research.duplicate(true),
		"unlocked":unlocked.duplicate(),
		"log":log_entries.duplicate(true),
		"outcome":outcome,
		"rng_state":str(rng.state),
		"last_day":last_day,
		"emergencies":emergencies.duplicate(true),
		"emergency_timer":emergency_timer,
		"abilities":abilities.duplicate(true),
		"missions":missions.duplicate(true),
		"next_mission_id":next_mission_id,
		"active_encounter":active_encounter.duplicate(true),
		"encounter_triggered":encounter_triggered
	}

func restore(data: Dictionary) -> bool:
	if data.get("version")!=1 or not data.get("stock") is Dictionary or not data.get("rooms") is Array:return false
	if data.rooms.size()!=10:return false
	for key in ["energy","food","water","scrap"]:
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
	
	stock=data.stock.duplicate(true)
	if "credits" not in stock: stock["credits"] = 50.0
	rooms=data.rooms.duplicate(true)
	survivors=int(data.survivors)
	if data.get("characters") is Array and data.characters.size() > 0:
		characters = data.characters.duplicate(true)
	else:
		_init_characters()
	next_char_id=int(data.get("next_char_id", 7))
	integrity=data.integrity;morale=data.morale;elapsed=data.elapsed;raid_in=data.raid_in;raids_survived=int(data.raids_survived)
	braced=bool(data.get("braced",false));expedition=ex.duplicate(true);research=re.duplicate(true);unlocked=data.unlocked.duplicate();log_entries=data.log.duplicate(true)
	outcome=data.get("outcome", "");last_day=int(data.get("last_day", day()));rng.state=int(data.get("rng_state", "7041"))
	if data.get("emergencies") is Array: emergencies = data.emergencies.duplicate(true)
	emergency_timer=float(data.get("emergency_timer", 45.0))
	if data.get("abilities") is Dictionary: abilities = data.abilities.duplicate(true)
	if data.get("missions") is Array and data.missions.size() > 0: missions = data.missions.duplicate(true)
	next_mission_id=int(data.get("next_mission_id", 1))
	if data.get("active_encounter") is Dictionary: active_encounter = data.active_encounter.duplicate(true)
	encounter_triggered=bool(data.get("encounter_triggered", false))
	sync_workers()
	revision+=1
	return true

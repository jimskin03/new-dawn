extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Bridge=preload("res://scripts/agent_bridge.gd")
var checks=0
var failures=0

func check(value: bool, label: String) -> void:
 checks+=1
 if not value:failures+=1;push_error("FAIL: "+label)

func _initialize() -> void:
 var sim=Sim.new()
 var before=sim.snapshot()
 for invalid in [{"action":"build","args":{"room":-1,"kind":"lab"}}, {"action":"build","args":{"room":5.5,"kind":"lab"}}, {"action":"build","args":{"room":5,"kind":"command"}}, {"action":"assign","args":{"room":0,"delta":2}}, {"action":"assign","args":{"room":"0","delta":1}}, {"action":"give_scrap","args":{}}, {"action":"step","args":{"seconds":31}}, {"action":"step","args":{"seconds":-1}}, {"action":"speed","args":{"rate":3}}, {"action":"new_game","args":{"confirm":false}}, {"action":"save","args":{"path":"C:/outside.json"}}]:
  check(Bridge.validate_action(invalid.action,invalid.args)!="","reject invalid "+str(invalid))
 check(sim.snapshot()==before,"validation does not change state")
 var args=JSON.parse_string('{"room":0,"delta":1}')
 check(Bridge.apply_model_action(sim,"assign",args)=="" and sim.rooms[0].workers==2,"JSON floating numbers work for assignment")
 check(Bridge.validate_action("speed",JSON.parse_string('{"rate":4}'))=="","JSON floating numbers work for speed")
 check(Bridge.apply_model_action(sim,"build",{"room":5,"kind":"lab"})=="","same construction operation")
 check(sim.stock.scrap==180 and sim.rooms[5].build_left==14,"ordinary construction cost and timer")
 check(Bridge.apply_model_action(sim,"assign",{"room":5,"delta":1})!="","construction prevents staffing")
 sim.tick(15)
 check(Bridge.apply_model_action(sim,"assign",{"room":5,"delta":1})=="","completed room accepts staffing")
 check(Bridge.apply_model_action(sim,"research",{"key":"relay"})!="","relay prerequisite enforced")
 var holder=Control.new();holder.set_script(load("res://scripts/main.gd"));holder.sim=sim
 var bridge=Bridge.new();bridge.game=holder
 before=sim.snapshot()
 var actions=bridge.available_actions()
 check(actions.size()>0,"reports legal gameplay actions")
 check(sim.snapshot()==before,"legal action observation never mutates live state or RNG")
 for candidate in actions:
  var trial=Sim.new();trial.restore(before)
  check(Bridge.apply_model_action(trial,candidate.action,candidate.args)=="","advertised action is legal")
 check(bridge._execute("step",{"seconds":1})!="","step requires pause")
 holder.speed=0;holder.modal="help"
 check(bridge._execute("step",{"seconds":1})!="","step respects modal pause")
 holder.modal=""
 check(bridge._execute("step",{"seconds":1})=="","step uses real simulation")
 check(sim.elapsed==16,"step advances exact game seconds")
 var state=bridge.live_state()
 check(state.simulation.rooms[5].id==5 and state.simulation.rooms[5].chamber==6,"room IDs map to GUI chamber numbers")
 check(not state.ui.visible and not state.ui.advancing,"headless and paused state are explicit")
 holder.free();bridge.free()
 print("BRIDGE_TESTS: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var failures=0
var checks=0

func check(condition: bool, label: String) -> void:
 checks+=1
 if not condition:failures+=1;push_error("FAIL: "+label)

func _initialize() -> void:
 var s=Sim.new()
 check(s.idle_workers()==2,"initial staffing leaves two scavengers")
 var start=s.stock.duplicate()
 s.tick(10)
 check(s.stock.energy>start.energy and s.stock.food>start.food and s.stock.water>start.water,"initial shelter is sustainable")
 check(s.assign(0,1)=="" and s.assign(0,1)=="","workers can be assigned")
 check(s.assign(0,1)!="","room capacity enforced")
 check(s.idle_workers()==0,"no phantom workers")
 check(s.start_expedition("depot")!="","staff cannot work inside and outside at once")
 s.assign(0,-1);s.assign(0,-1)
 check(s.start_expedition("depot")=="","scavenging dispatch")
 check(s.idle_workers()==0,"expedition reserves two workers")
 var food_after=s.stock.food
 check(s.start_expedition("depot")!="" and s.stock.food==food_after,"duplicate dispatch cannot charge food")
 s.tick(33)
 check(s.expedition.is_empty() and s.idle_workers()==2,"return releases crew")
 check(s.stock.scrap>start.scrap+85,"scavenging loot credited")
 var scrap=s.stock.scrap
 check(s.build_room(0,"lab")!="" and s.stock.scrap==scrap,"occupied rooms protected")
 check(s.build_room(5,"lab")=="","lab construction")
 check(s.assign(5,1)!="","cannot staff construction")
 check(s.start_research("efficiency")!="","cannot research without scientist")
 s.tick(14)
 check(s.has_room("lab"),"room completion")
 check(s.assign(5,1)=="","staff completed room")
 check(s.start_research("relay")!="","research prerequisite enforced")
 check(s.start_research("efficiency")=="","research begins")
 s.assign(5,-1);var left=s.research.left;s.tick(5)
 check(s.research.left==left,"unstaffed research pauses")
 s.assign(5,1);s.tick(29)
 check("efficiency" in s.unlocked,"research completes")
 check(s.rates().water>Sim.new().rates().water,"efficiency changes production")
 s.stock.scrap=999
 check(s.upgrade_room(1)=="" and s.upgrade_room(1)=="","upgrades work")
 check(s.upgrade_room(1)!="","upgrade cap")
 check(s.brace()=="","fortify consumes energy")
 var energy=s.stock.energy
 check(s.brace()!="" and s.stock.energy==energy,"fortify cannot charge twice")
 s.raid_in=1;s.tick(1.1)
 check(s.raids_survived>=1 and not s.braced,"raid resolves and consumes fortification")
 check(s.repair()=="" and s.integrity==100,"repair restores health")

 # JSON roundtrip and RNG continuity, including expedition and research timers.
 s.assign(0,-1);s.start_expedition("outpost");s.start_research("relay")
 var encoded=JSON.stringify(s.snapshot(),"",true,true);var saved=JSON.parse_string(encoded);var loaded=Sim.new()
 check(loaded.restore(saved),"valid save restores")
 check(loaded.idle_workers()==s.idle_workers() and loaded.day()==s.day(),"staffing and clock survive save")
 s.tick(50);loaded.tick(50)
 var same_stock=true
 for key in s.stock:same_stock=same_stock and is_equal_approx(s.stock[key],loaded.stock[key])
 check(same_stock and s.survivors==loaded.survivors,"save retains deterministic progression")
 var before=loaded.snapshot();saved.rooms[0].kind="corrupt"
 check(not loaded.restore(saved) and loaded.snapshot()==before,"bad save rejected atomically")
 check(not loaded.restore({"version":1}),"truncated save rejected")

 # Complete the actual progression from a new run, using only legal actions.
 var campaign=Sim.new()
 check(campaign.start_expedition("depot")=="","campaign expedition")
 check(campaign.build_room(5,"lab")=="","campaign lab")
 campaign.tick(33)
 check(campaign.assign(5,1)=="","campaign scientist")
 check(campaign.start_research("efficiency")=="","campaign efficiency")
 campaign.tick(29)
 check(campaign.start_research("relay")=="","campaign relay")
 campaign.tick(46)
 check("relay" in campaign.unlocked,"campaign relay online")
 while campaign.elapsed<541 and campaign.outcome=="":
  if campaign.raid_in<10 and not campaign.braced:campaign.brace()
  if campaign.integrity<75:campaign.repair()
  campaign.tick(1)
 check(campaign.outcome=="victory","complete seven day campaign is winnable")
 var frozen=campaign.snapshot();campaign.tick(300)
 check(campaign.snapshot()==frozen,"ended run stops simulation")
 check(campaign.build_room(6,"dorm")!="","ended run blocks mutations")
 var bad=Sim.new();bad.stock.food=0;bad.stock.water=0
 bad.rooms[2].workers=0;bad.rooms[3].workers=0;bad.raid_in=9999
 bad.tick(900)
 check(bad.outcome=="defeat","neglect has a loss condition")
 for amount in bad.stock.values():check(amount>=0,"resources never go negative")
 print("SIM_TESTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

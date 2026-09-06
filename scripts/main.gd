extends Control
## Bespoke resolution-independent interface over Blender-rendered dioramas.
const Sim = preload("res://scripts/simulation.gd")
const AgentBridge = preload("res://scripts/agent_bridge.gd")
const BG = Color("101b21")
const PANEL = Color("19292f")
const LINE = Color("34464a")
const INK = Color("f1eee4")
const MUTED = Color("99afb2")
const GOLD = Color("e8bb72")
const TEAL = Color("85cbbf")
const RED = Color("e89580")
const SAVE_PATH = "user://shelter_07.json"
var save_path = SAVE_PATH
var sim = Sim.new()
var font: Font
var textures: Dictionary = {}
var hitboxes: Array = []
var mouse = Vector2(-1,-1)
var selected = 0
var tab = "Shelter"
var depth = 0
var speed = 1
var clock_time = 0.0
var save_timer = 0.0
var toast = ""
var toast_left = 0.0
var modal = ""
var muted = false
var auto_load = true
var audio_player: AudioStreamPlayer
var hover_tip = ""
var ui_refresh = 0.0
var captured_outcome = false
var test_mode = false
var rocks: Array = []
var agent_bridge: Node

func _ready() -> void:
 font = load("res://assets/fonts/Inter.woff2")
 if font==null:font=ThemeDB.fallback_font
 for key in ["surface","command","power","water","food","dorm","lab","medbay","workshop","security","empty"]:
  textures[key]=load("res://assets/renders/"+key+".png")
 var random=RandomNumberGenerator.new();random.seed=93
 for i in range(400):
  rocks.append({"x":random.randf_range(45,1115),"y":random.randf_range(376,908),"r":random.randf_range(5,15),"shade":random.randf_range(.10,.19)})
 audio_player=AudioStreamPlayer.new();add_child(audio_player);audio_player.volume_db=-22
 test_mode="--smoke" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--test-play" in OS.get_cmdline_user_args() or "--save-smoke" in OS.get_cmdline_user_args() or "--gallery" in OS.get_cmdline_user_args()
 var agent_dir=ProjectSettings.globalize_path("res://").path_join(".agent")
 var launch_args=OS.get_cmdline_user_args()
 for i in range(launch_args.size()-1):
  if launch_args[i]=="--agent-dir":agent_dir=launch_args[i+1]
  elif launch_args[i]=="--save-path":save_path=launch_args[i+1]
 if not test_mode:
  if FileAccess.file_exists(save_path):load_game(false)
  else:modal="help"
 if test_mode:speed=0
 if "--agent-paused" in launch_args:speed=0;modal=""
 set_process_input(true)
 get_tree().auto_accept_quit=false
 if "--capture" in OS.get_cmdline_user_args():_capture.call_deferred()
 if "--smoke" in OS.get_cmdline_user_args():_smoke.call_deferred()
 if "--save-smoke" in OS.get_cmdline_user_args():_save_smoke.call_deferred()
 if "--gallery" in OS.get_cmdline_user_args():_gallery.call_deferred()
 if not test_mode and "--no-agent" not in launch_args:
  agent_bridge=AgentBridge.new();add_child(agent_bridge)
  var bridge_error: String=agent_bridge.start(self,agent_dir)
  if bridge_error!="":notify_user(bridge_error)

func _notification(what: int) -> void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST:
  if not test_mode:save_game(false)
  get_tree().quit()

func _process(dt: float) -> void:
 clock_time+=dt;toast_left=maxf(0,toast_left-dt);save_timer+=dt
 if modal=="" and speed>0:sim.tick(dt*speed)
 sync_outcome()
 if save_timer>20 and not test_mode:save_timer=0;save_game(false)
 ui_refresh+=dt
 if ui_refresh>=1.0/30:ui_refresh=0;queue_redraw()

func sync_outcome() -> void:
 if sim.outcome!="" and not captured_outcome:
  captured_outcome=true;modal=sim.outcome;save_game(false)

func _input(event: InputEvent) -> void:
 if event is InputEventMouseMotion:
  mouse=event.position
  var hover=false
  for hit in hitboxes:
   if hit.rect.has_point(mouse):hover=true;break
  mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if hover else Control.CURSOR_ARROW
 elif event is InputEventMouseButton and event.pressed:
  mouse=event.position
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and mouse.x<1140 and modal=="":depth=mini(2,depth+1)
  elif event.button_index==MOUSE_BUTTON_WHEEL_UP and mouse.x<1140 and modal=="":depth=maxi(0,depth-1)
  elif event.button_index==MOUSE_BUTTON_LEFT:
   for i in range(hitboxes.size()-1,-1,-1):
    if hitboxes[i].rect.has_point(mouse):
     var callback: Callable=hitboxes[i].action
     callback.call();play_click();break
  queue_redraw()
 elif event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_ESCAPE:modal="" if modal!="" else "help"
  elif modal=="":
   match event.keycode:
    KEY_SPACE:toggle_pause()
    KEY_1:speed=1
    KEY_2:speed=2
    KEY_3:speed=4
    KEY_B:set_tab("Build")
    KEY_R:set_tab("Research")
    KEY_M:set_tab("Map")
    KEY_P:set_tab("People")
    KEY_S:save_game(true)
    KEY_F11:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
  queue_redraw()

func box(r: Rect2, color: Color, border: Color=Color.TRANSPARENT, radius: int=10, width: int=1) -> void:
 var style=StyleBoxFlat.new();style.bg_color=color;style.border_color=border;style.set_border_width_all(width if border.a>0 else 0);style.set_corner_radius_all(radius)
 draw_style_box(style,r)

func txt(value: String, x: float, y: float, size_px: int=18, color: Color=INK, width: float=-1) -> void:
 draw_string(font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,width,size_px,color)

func centered(value: String, r: Rect2, size_px: int=18, color: Color=INK) -> void:
 var w=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
 txt(value,r.position.x+(r.size.x-w)/2,r.position.y+(r.size.y+size_px*.7)/2,size_px,color)

func paragraph(value: String, x: float, y: float, width: float, size_px: int=17, color: Color=MUTED, line_h: float=25) -> float:
 var line=""
 for word in value.split(" "):
  if font.get_string_size(line+word,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x>width and line!="":
   txt(line,x,y,size_px,color);y+=line_h;line=""
  line+=word+" "
 if line!="":txt(line,x,y,size_px,color)
 return y+line_h

func meter(x: float,y: float,w: float,value: float,color: Color=TEAL,h: float=5) -> void:
 box(Rect2(x,y,w,h),Color("0d171c"),Color.TRANSPARENT,2)
 if value>0:box(Rect2(x,y,w*clampf(value,0,1),h),color,Color.TRANSPARENT,2)

func button(r: Rect2, title: String, callback: Callable, primary: bool=false, disabled: bool=false, hint: String="", size_px: int=17) -> void:
 var over=r.has_point(mouse) and not disabled
 var color=GOLD if primary else Color("263b42")
 if over:color=color.lightened(.12)
 if disabled:color=Color("233138")
 box(r,color,Color("ddc095") if primary and not disabled else LINE,7)
 centered(title,r,size_px,Color("152329") if primary and not disabled else (MUTED.darkened(.30) if disabled else INK))
 if not disabled:hitboxes.append({"rect":r,"action":callback})
 if over and hint!="":hover_tip=hint

func icon(kind: String,p: Vector2,color: Color=GOLD,scale_v: float=1.0) -> void:
 var s=scale_v
 match kind:
  "energy","power":
   var points=PackedVector2Array([p+Vector2(2,-13)*s,p+Vector2(-9,2)*s,p+Vector2(-1,2)*s,p+Vector2(-4,14)*s,p+Vector2(10,-3)*s,p+Vector2(2,-3)*s])
   draw_colored_polygon(points,color)
  "water":
   draw_colored_polygon(PackedVector2Array([p+Vector2(0,-14)*s,p+Vector2(-8,0)*s,p+Vector2(8,0)*s]),color);draw_circle(p+Vector2(0,3)*s,8*s,color,true,-1,true)
  "food":
   draw_line(p+Vector2(0,11)*s,p+Vector2(0,-9)*s,color,2*s,true)
   draw_colored_polygon(PackedVector2Array([p+Vector2(0,3)*s,p+Vector2(-11,-1)*s,p+Vector2(-12,-10)*s,p+Vector2(-3,-7)*s]),color)
   draw_colored_polygon(PackedVector2Array([p+Vector2(0,-1)*s,p+Vector2(11,-6)*s,p+Vector2(12,-14)*s,p+Vector2(3,-11)*s]),color)
  "scrap","Build":
   draw_line(p+Vector2(-7,10)*s,p+Vector2(5,-5)*s,color,5*s,true)
   draw_colored_polygon(PackedVector2Array([p+Vector2(-3,-12)*s,p+Vector2(12,0)*s,p+Vector2(16,-5)*s,p+Vector2(2,-17)*s]),color)
  "People","dorm":
   draw_circle(p+Vector2(0,-7)*s,5*s,color,true,-1,true);draw_arc(p+Vector2(0,10)*s,9*s,PI,TAU,16,color,5*s,true)
  "Research","lab":
   draw_polyline(PackedVector2Array([p+Vector2(-4,-12)*s,p+Vector2(-4,-3)*s,p+Vector2(-11,10)*s,p+Vector2(11,10)*s,p+Vector2(4,-3)*s,p+Vector2(4,-12)*s]),color,2*s,true);draw_line(p+Vector2(-7,-12)*s,p+Vector2(7,-12)*s,color,2*s,true);draw_line(p+Vector2(-5,3)*s,p+Vector2(5,3)*s,color,3*s,true)
  "Map":
   draw_arc(p+Vector2(0,-4)*s,8*s,0,TAU,24,color,2*s,true);draw_line(p+Vector2(-6,2)*s,p+Vector2(0,13)*s,color,2*s,true);draw_line(p+Vector2(6,2)*s,p+Vector2(0,13)*s,color,2*s,true);draw_circle(p+Vector2(0,-4)*s,2*s,color,true,-1,true)
  "Shelter":
   draw_polyline(PackedVector2Array([p+Vector2(-12,1)*s,p+Vector2(0,-11)*s,p+Vector2(12,1)*s]),color,2.5*s,true);draw_polyline(PackedVector2Array([p+Vector2(-9,-1)*s,p+Vector2(-9,12)*s,p+Vector2(9,12)*s,p+Vector2(9,-1)*s]),color,2.5*s,true)
  _:
   draw_arc(p,10*s,0,TAU,24,color,2*s,true);draw_line(p+Vector2(-5,0)*s,p+Vector2(5,0)*s,color,2*s,true);draw_line(p+Vector2(0,-5)*s,p+Vector2(0,5)*s,color,2*s,true)

func _draw() -> void:
 if font==null:return
 hitboxes.clear();hover_tip=""
 draw_rect(Rect2(0,0,1600,1000),BG)
 draw_header();draw_bunker();draw_sidebar();draw_footer()
 if modal!="":draw_modal()
 if toast_left>0:
  var w=minf(1000,font.get_string_size(toast,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+46)
  box(Rect2(800-w/2,865,w,48),Color("294740"),TEAL,8);centered(toast,Rect2(800-w/2,865,w,48),17)
 if hover_tip!="" and modal=="":
  var w=minf(510,font.get_string_size(hover_tip,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+28)
  var x=clampf(mouse.x-w/2,14,1586-w);var y=minf(mouse.y+22,964)
  box(Rect2(x,y,w,30),Color("0d181e"),LINE,5);centered(hover_tip,Rect2(x,y,w,30),14,MUTED)

func draw_header() -> void:
 box(Rect2(28,25,55,55),Color("263b3e"),Color("57716a"),15)
 icon("Shelter",Vector2(55,52),GOLD,1.40)
 txt("NEW DAWN",100,51,29)
 txt("S H E L T E R   0 7  /  A S H F A L L   V A L L E Y",101,77,10,MUTED)
 var net=sim.rates();var i=0
 for key in ["energy","food","water","scrap"]:
  var x=449+i*176
  box(Rect2(x,23,165,65),PANEL,LINE,9)
  var col=Color(Sim.ROOM_TYPES[{"energy":"power","food":"food","water":"water","scrap":"workshop"}[key]].color)
  icon(key,Vector2(x+25,51),col,.85)
  txt(str(int(sim.stock[key])),x+48,52,24)
  txt(key.to_upper(),x+48,72,10,MUTED)
  txt(("+" if net[key]>=0 else "")+"%.1f" % net[key]+"/s",x+108,72,11,col if net[key]>=0 else RED)
  meter(x+13,81,139,float(sim.stock[key])/sim.max_stock(key),col,2)
  i+=1
 draw_circle(Vector2(1181,40),4,TEAL,true,-1,true)
 txt("DAY %02d" % sim.day(),1194,47,18)
 txt("%02d:%02d" % [6+int(fmod(sim.elapsed,90)/90*18),int(fmod(sim.elapsed,5)*12)],1194,71,13,MUTED)
 button(Rect2(1312,26,44,54),"Ⅱ" if speed>0 else "▶",toggle_pause,false,false,"Pause / resume · Space",19)
 for n in range(3):
  var val=[1,2,4][n];button(Rect2(1364+n*51,26,45,54),str(val)+"×",func():speed=val,speed==val,false,"Game speed · "+str(n+1),15)
 button(Rect2(1527,26,44,54),"?",func():modal="help",false,false,"How to play",21)
 draw_line(Vector2(28,104),Vector2(1571,104),LINE,1,true)

func draw_bunker() -> void:
 box(Rect2(26,119,1108,804),Color("211e1b"),LINE,12)
 draw_texture_rect(textures.surface,Rect2(27,120,1106,251),false)
 # Soft interface strip over the sky, leaving the entrance visible.
 box(Rect2(45,137,204,30),Color(.06,.10,.12,.85),Color.TRANSPARENT,15)
 draw_circle(Vector2(61,152),3,TEAL,true,-1,true);txt("EXTERIOR / SECTOR 07",73,157,11,INK)
 box(Rect2(935,137,179,30),Color(.06,.10,.12,.85),Color.TRANSPARENT,15)
 txt("CLEAR  /  32°C",956,157,12,INK)
 if agent_bridge!=null and agent_bridge.active:
  box(Rect2(272,137,145,30),Color(.06,.10,.12,.85),TEAL,15)
  draw_circle(Vector2(286,152),3,TEAL,true,-1,true);txt("AGENT CONNECTED",297,157,10,TEAL)
 # Airborne dust glints drift through the surface view.
 for n in range(22):
  var x=40+fmod(n*53.4+clock_time*(5+n%3),1080);var y=193+fmod(n*31.6,157)
  draw_circle(Vector2(x,y+sin(clock_time+n)*3),1,Color(1,.86,.56,.19),true,-1,true)
 for rock in rocks:
  var col=Color(rock.shade,rock.shade*.87,rock.shade*.75)
  draw_colored_polygon(PackedVector2Array([Vector2(rock.x-rock.r,rock.y),Vector2(rock.x-rock.r*.4,rock.y-rock.r*.5),Vector2(rock.x+rock.r*.8,rock.y-rock.r*.2),Vector2(rock.x+rock.r,rock.y+rock.r*.3),Vector2(rock.x,rock.y+rock.r*.5)]),col)
 for row in range(3):
  var y=365+row*183
  for col in range(2):
   var index=(row+depth)*2+col;draw_room(index,Rect2(42+col*505,y,495,176))
  # Continuous amber elevator shaft.
  box(Rect2(1060,y,54,176),Color("131c1e"),Color("53605a"),6,2)
  box(Rect2(1068,y+12,38,148),Color("2b3331"),Color("5e6456"),3)
  draw_line(Vector2(1087,y+13),Vector2(1087,y+158),Color("0a1519"),2)
  for ex in [1072,1101]:
   draw_line(Vector2(ex,y+24),Vector2(ex,y+145),Color(.96,.52,.16,.15),8,true)
   draw_line(Vector2(ex,y+24),Vector2(ex,y+145),GOLD,2,true)
  box(Rect2(1081,y+75,12,29),Color("0f191b"),Color.TRANSPARENT,2)
  draw_circle(Vector2(1087,y+84),2,TEAL,true,-1,true)
  txt("%02d" % (row+depth+1),1079,y+171,9,MUTED)
 # Move through five underground floors, three visible at a time.
 box(Rect2(850,337,264,26),Color(.05,.08,.09,.9),Color.TRANSPARENT,5)
 txt("DEPTH  %02d–%02d" % [depth+1,depth+3],865,355,11,MUTED)
 button(Rect2(995,337,52,26),"↑",func():depth=maxi(0,depth-1),false,depth==0,"Scroll up",15)
 button(Rect2(1053,337,52,26),"↓",func():depth=mini(2,depth+1),false,depth==2,"Scroll down for more chambers",15)
 if sim.raid_in<25:
  box(Rect2(275,137,461,44),Color("612f27"),RED,7)
  txt("!   RAIDERS APPROACHING",291,157,14,INK)
  txt("Impact in %ds · Fortify the entrance" % ceili(sim.raid_in),291,174,11,Color("e8b4a4"))

func draw_room(index: int, r: Rect2) -> void:
 var room: Dictionary=sim.rooms[index];var kind: String=room.kind
 var over=r.has_point(mouse);var active=selected==index
 box(r.grow(3),Color("10191c"),GOLD if active else (Color("a9b9b2") if over else Color("56605a")),7,2)
 draw_texture_rect(textures["empty" if kind=="" else kind],r,false)
 if kind=="":
  draw_rect(r,Color(.03,.07,.09,.45))
  draw_arc(r.get_center()-Vector2(0,12),22,0,TAU,40,TEAL,1.3,true)
  txt("+",r.get_center().x-9,r.get_center().y-3,29,TEAL)
  centered("BUILD A NEW ROOM",Rect2(r.position.x,r.position.y+110,r.size.x,28),13,INK)
  centered("Expand a little. Hope a little.",Rect2(r.position.x,r.position.y+135,r.size.x,23),11,MUTED)
 else:
  var tint=Color(Sim.ROOM_TYPES[kind].color)
  var bottom=Rect2(r.position.x+2,r.end.y-30,r.size.x-4,29)
  box(bottom,Color(.04,.08,.10,.95),Color.TRANSPARENT,2)
  icon(kind,Vector2(r.position.x+20,r.end.y-15),tint,.54)
  txt(Sim.ROOM_TYPES[kind].name,r.position.x+36,r.end.y-10,14)
  txt("LV. "+str(room.level),r.end.x-109,r.end.y-10,10,MUTED)
  for n in range(3):draw_circle(Vector2(r.end.x-54+n*14,r.end.y-15),3.5,tint if n<int(room.workers) else Color("415050"),true,-1,true)
  if room.build_left>0:
   draw_rect(r,Color(.08,.07,.03,.42));centered("UNDER CONSTRUCTION",Rect2(r.position.x,r.position.y+65,r.size.x,25),16,GOLD)
   centered("%ds remaining" % ceili(room.build_left),Rect2(r.position.x,r.position.y+91,r.size.x,22),12,INK)
   meter(r.position.x+85,r.position.y+124,r.size.x-170,1-room.build_left/room.build_total,GOLD,4)
  elif room.workers>0 and Sim.ROOM_TYPES[kind].output!="":
   var pulse=.50+sin(clock_time*2+index)*.18
   box(Rect2(r.end.x-99,r.position.y+10,86,22),Color(.03,.08,.09,.90),Color.TRANSPARENT,11)
   draw_circle(Vector2(r.end.x-86,r.position.y+21),2.5,Color(tint,pulse+.25),true,-1,true)
   txt("+%.2f/s" % sim.gross_output(index),r.end.x-77,r.position.y+25,11,tint)
 hitboxes.append({"rect":r,"action":func():select_room(index)})

func draw_sidebar() -> void:
 var x=1154.0
 # Persistent objective and status.
 box(Rect2(x,120,419,128),PANEL,LINE,10)
 txt("OUR NEXT CHAPTER",x+20,146,10,GOLD)
 var obj=sim.objective();txt(obj.title,x+20,174,21)
 paragraph(obj.desc,x+20,198,375,13,MUTED,18)
 meter(x+20,230,378,obj.progress,GOLD,3)
 box(Rect2(x,260,419,96),PANEL,LINE,10)
 icon("People",Vector2(x+27,290),TEAL,.68)
 txt("%d / %d" % [sim.survivors,sim.capacity()],x+47,295,20)
 txt("SURVIVORS",x+47,315,9,MUTED)
 txt("%d%%" % int(sim.morale),x+190,295,20,TEAL)
 txt("MORALE",x+190,315,9,MUTED)
 txt("%d%%" % int(sim.integrity),x+314,295,20,TEAL if sim.integrity>50 else RED)
 txt("INTEGRITY",x+314,315,9,MUTED)
 meter(x+20,336,378,sim.integrity/100,TEAL if sim.integrity>50 else RED,3)
 box(Rect2(x,370,419,543),PANEL,LINE,10)
 match tab:
  "Build":draw_build(x)
  "People":draw_people(x)
  "Research":draw_research(x)
  "Map":draw_map(x)
  _:draw_inspector(x)

func draw_inspector(x: float) -> void:
 var r: Dictionary=sim.rooms[selected];var kind: String=r.kind
 if kind=="":
  txt("UNCLAIMED SPACE",x+22,400,10,GOLD);txt("Room to grow",x+22,432,26)
  paragraph("An excavated chamber, waiting for a purpose. Build a room to give your survivors a better tomorrow.",x+22,466,368,16)
  draw_texture_rect(textures.empty,Rect2(x+20,540,379,160),false)
  button(Rect2(x+22,727,375,48),"Choose a room  →",func():set_tab("Build"),true)
  return
 var info: Dictionary=Sim.ROOM_TYPES[kind];var tint=Color(info.color)
 txt("ROOM OVERVIEW  /  LEVEL "+str(r.level),x+22,399,10,tint)
 txt(info.name,x+22,432,25)
 paragraph(info.desc,x+22,461,369,15,MUTED,23)
 draw_line(Vector2(x+22,528),Vector2(x+397,528),LINE,1)
 if r.build_left>0:
  txt("Construction in progress",x+22,560,17,GOLD);meter(x+22,580,375,1-r.build_left/r.build_total,GOLD)
  txt("%d seconds remaining" % ceili(r.build_left),x+22,613,14,MUTED)
 elif kind=="dorm":
  txt("A bed for everyone",x+22,560,18)
  txt("+%d survivor capacity · no staff required" % (4*int(r.level)),x+22,589,14,tint)
 else:
  txt("ASSIGNED SURVIVORS",x+22,554,10,MUTED)
  for n in range(3):
   var px=x+22+n*65
   box(Rect2(px,569,53,55),Color("2a4147") if n<r.workers else Color("152329"),tint if n<r.workers else LINE,8)
   icon("People",Vector2(px+26,595),tint if n<r.workers else Color("496068"),.8)
  button(Rect2(x+242,573,48,46),"−",func():action(sim.assign(selected,-1)),false,r.workers==0,"Return a survivor to the available pool",23)
  button(Rect2(x+300,573,48,46),"+",func():action(sim.assign(selected,1)),false,r.workers>=3 or sim.idle_workers()==0,"Assign an available survivor",23)
  txt("%d assigned  /  %d available" % [r.workers,sim.idle_workers()],x+22,649,13,MUTED)
  if info.output!="":txt("Producing  +%.2f %s / sec" % [sim.gross_output(selected),info.output],x+22,680,16,tint)
  elif kind=="lab":txt("%d scientist(s) · Research tab to begin" % sim.scientist_count(),x+22,680,14,tint)
  elif kind=="security":txt("+%d defense from this room" % (18*r.workers*r.level),x+22,680,16,tint)
  else:txt("Restores morale and shelter integrity",x+22,680,14,tint)
 if r.build_left<=0:
  button(Rect2(x+22,710,375,46),"Upgrade to level %d    /    %d scrap" % [r.level+1,sim.upgrade_cost(selected)] if r.level<3 else "Maximum level reached",func():action(sim.upgrade_room(selected)),true,r.level>=3 or sim.stock.scrap<sim.upgrade_cost(selected),"Upgrades increase production or room effectiveness",15)
 draw_line(Vector2(x+22,776),Vector2(x+397,776),LINE,1)
 txt("ENTRANCE DEFENSE",x+22,802,10,MUTED);txt(str(sim.defense()),x+342,805,20,TEAL)
 txt("Next raid in %ds" % ceili(sim.raid_in),x+22,828,13,RED if sim.raid_in<25 else MUTED)
 button(Rect2(x+22,845,183,42),"Fortify · 30 energy",func():action(sim.brace()),false,sim.braced or sim.stock.energy<30,"+45 defense for the next raid",13)
 button(Rect2(x+215,845,182,42),"Repair · 35 scrap",func():action(sim.repair()),false,sim.integrity>=100 or sim.stock.scrap<35,"Restore 25 integrity",13)

func draw_build(x: float) -> void:
 txt("BUILD A BETTER TOMORROW",x+22,399,10,GOLD);txt("Expand your shelter",x+22,432,24)
 var empty=sim.rooms[selected].kind==""
 txt("Chamber %02d selected" % (selected+1) if empty else "Select an empty chamber in the cutaway.",x+22,458,13,MUTED)
 var kinds=["lab","workshop","security","dorm","power","water","food","medbay"]
 for i in range(kinds.size()):
  var kind: String=kinds[i];var info: Dictionary=Sim.ROOM_TYPES[kind]
  var px=x+20+(i%2)*194;var py=475+int(i/2)*102
  box(Rect2(px,py,184,92),Color("142329"),LINE,7)
  draw_texture_rect(textures[kind],Rect2(px+1,py+1,182,47),false)
  txt(info.name,px+10,py+65,12)
  var can_build=empty and sim.stock.scrap>=info.cost
  txt(str(info.cost)+" scrap",px+10,py+82,10,GOLD if sim.stock.scrap>=info.cost else RED)
  button(Rect2(px+135,py+54,38,29),"+",func():build(kind),can_build,not can_build,info.desc,19)
 txt("14s to build · staff new rooms after construction",x+22,902,11,MUTED)

func draw_people(x: float) -> void:
 txt("THE PEOPLE OF SHELTER 07",x+22,399,10,TEAL);txt("Stronger together",x+22,432,25)
 txt("%d available · %d on expedition" % [sim.idle_workers(),2 if not sim.expedition.is_empty() else 0],x+22,460,14,MUTED)
 var names=["Mara","Eli","Jun","Sana","Noah","Iris","Ari","Luca","Rae","Finn"]
 var roles: Array=[]
 for r in sim.rooms:
  for n in range(int(r.workers)):roles.append(Sim.ROOM_TYPES[r.kind].name)
 if not sim.expedition.is_empty():roles.append("Scavenging expedition");roles.append("Scavenging expedition")
 while roles.size()<sim.survivors:roles.append("Available for assignment")
 for i in range(mini(sim.survivors,7)):
  var y=484+i*48
  box(Rect2(x+22,y,37,37),Color("31474c"),LINE,19);centered(names[i%10].left(1),Rect2(x+22,y,37,37),16,TEAL)
  txt(names[i%10],x+74,y+16,15);txt(roles[i],x+74,y+34,11,MUTED)
 txt("Select a room to assign or release its workers.",x+22,851,12,MUTED)
 txt("Grow your population: build beds, visit the outpost.",x+22,878,12,MUTED)

func draw_research(x: float) -> void:
 txt("KNOWLEDGE IS OUR WAY OUT",x+22,399,10,TEAL);txt("A brighter tomorrow",x+22,432,25)
 txt("%d scientist(s) assigned" % sim.scientist_count(),x+22,460,14,MUTED)
 var i=0
 for key in ["efficiency","defense","relay"]:
  var info: Dictionary=Sim.RESEARCH[key];var y=483+i*126
  box(Rect2(x+20,y,379,115),Color("142329"),LINE,7)
  txt(info.name,x+34,y+25,17,TEAL if key in sim.unlocked else INK)
  paragraph(info.desc,x+34,y+48,345,12,MUTED,17)
  var active=sim.research.get("key", "")==key
  if active:
   meter(x+34,y+88,348,1-sim.research.left/sim.research.total,TEAL,4)
   txt("%ds left" % ceili(sim.research.left/maxi(1,sim.scientist_count())) if sim.scientist_count()>0 and sim.stock.energy>0 else "Paused · needs a scientist and power",x+34,y+107,11,TEAL)
  else:
   var title="Completed" if key in sim.unlocked else "Research · %d scrap" % info.cost
   button(Rect2(x+34,y+76,348,28),title,func():action(sim.start_research(key)),false,key in sim.unlocked or not sim.research.is_empty() or sim.scientist_count()==0 or sim.stock.scrap<info.cost or (key=="relay" and "efficiency" not in sim.unlocked),"Requires a staffed lab and power",12)
  i+=1
 txt("Research pauses while the lab is unstaffed or unpowered.",x+22,889,11,MUTED)

func draw_map(x: float) -> void:
 txt("BEYOND THE BLAST DOORS",x+22,399,10,GOLD);txt("The wasteland calls",x+22,432,25)
 txt("2 available survivors + 12 food per expedition",x+22,460,13,MUTED)
 var area=Rect2(x+21,478,377,134);box(area,Color("172c30"),LINE,7)
 for n in range(11):draw_line(Vector2(x+28+n*35,482),Vector2(x+28+n*35,607),Color("243c3e"),1)
 for n in range(4):draw_line(Vector2(x+24,490+n*32),Vector2(x+395,490+n*32),Color("243c3e"),1)
 var points=[Vector2(x+65,567),Vector2(x+167,510),Vector2(x+287,565),Vector2(x+345,515)]
 draw_polyline(PackedVector2Array(points),Color("657a68"),2,true)
 for p in points:draw_circle(p,5,GOLD,true,-1,true);draw_arc(p,12,0,TAU,24,Color("71836a"),1,true)
 txt("07",x+46,593,10,TEAL);txt("DEPOT",x+143,499,9,MUTED);txt("RESERVOIR",x+253,594,9,MUTED);txt("OUTPOST",x+319,499,9,MUTED)
 if not sim.expedition.is_empty():
  var ex: Dictionary=sim.expedition
  txt("Team en route: "+ex.route.capitalize(),x+22,646,18,TEAL)
  meter(x+22,667,375,1-ex.left/ex.total,TEAL,5)
  txt("Returning in %ds" % ceili(ex.left),x+22,699,14,MUTED)
  paragraph("The team is safe. Keep the shelter running until they return with supplies.",x+22,739,366,15)
 else:
  var i=0
  for route in ["depot","reservoir","outpost"]:
   var y=628+i*82
   txt({"depot":"Abandoned depot","reservoir":"Old reservoir","outpost":"Survivor outpost"}[route],x+23,y+14,16)
   txt({"depot":"85–115 scrap + 24 food · 32s","reservoir":"100 water + 42 food · 32s","outpost":"Recruit a survivor + supplies · 46s"}[route],x+23,y+35,11,MUTED)
   button(Rect2(x+301,y,96,42),"Dispatch",func():action(sim.start_expedition(route)),false,sim.idle_workers()<2 or sim.stock.food<12,"A team reserves two available survivors",12)
   i+=1

func draw_footer() -> void:
 box(Rect2(27,938,1107,47),Color("16252b"),LINE,9)
 var tabs=["Shelter","Build","People","Research","Map"]
 for i in range(tabs.size()):
  var title: String=tabs[i];var r=Rect2(32+i*219,942,211,39);var active=tab==title
  if active:box(r,Color("334842"),Color("63776a"),6)
  elif r.has_point(mouse):box(r,Color("263a3f"),Color.TRANSPARENT,6)
  icon(title,Vector2(r.position.x+43,r.position.y+20),GOLD if active else MUTED,.65)
  txt(title,r.position.x+66,r.position.y+25,15,GOLD if active else INK)
  hitboxes.append({"rect":r,"action":func():set_tab(title)})
 button(Rect2(1155,938,102,47),"Save",func():save_game(true),false,false,"Autosaves every 20 seconds · S",14)
 button(Rect2(1266,938,102,47),"Journal",func():modal="journal",false,false,"Read shelter events",14)
 button(Rect2(1377,938,90,47),"Sound" if not muted else "Muted",func():muted=not muted,false,false,"Toggle interface sounds",13)
 button(Rect2(1476,938,97,47),"Menu",func():modal="menu",false,false,"Save, load, or restart",14)

func draw_modal() -> void:
 hitboxes.clear()
 draw_rect(Rect2(0,0,1600,1000),Color(.018,.035,.044,.86))
 var r=Rect2(446,186,708,626);box(r,PANEL,Color("566762"),14,2)
 button(Rect2(1093,205,39,37),"×",func():modal="",false,false,"Close · Escape",24)
 if modal=="help":
  txt("WELCOME TO SHELTER 07",484,238,11,GOLD);txt("Keep hope alive.",484,284,35)
  paragraph("Restore the long-range relay and survive until day 7 to guide a rescue convoy home.",484,324,620,19,INK,28)
  var steps=[
   ["01  KEEP THE SHELTER RUNNING","Food and water feed six survivors. Staff production rooms with the + button; watch the resource rates above."],
   ["02  BUILD YOUR WAY FORWARD","Select an empty chamber, build a Research Lab, then assign a scientist. Research Closed-loop systems and the relay."],
   ["03  PREPARE FOR THE WASTELAND","Send two free survivors scavenging. Fortify before raids and repair damage. Scroll the bunker to reach more chambers."]]
  for i in range(steps.size()):
   var y=399+i*99;txt(steps[i][0],484,y,12,TEAL);paragraph(steps[i][1],484,y+25,620,15,MUTED,23)
  txt("Space  pause    1 / 2 / 3  speed    B  build    R  research    M  map",484,714,12,MUTED)
  txt("S  save    Esc  help / close    F11  fullscreen    Mouse wheel  floors",484,739,12,MUTED)
  button(Rect2(484,760,632,34),"Let’s build a tomorrow  →",func():modal="",true,false,"",15)
 elif modal=="journal":
  txt("SHELTER JOURNAL",484,239,11,GOLD);txt("Every day is a story.",484,282,30)
  var y=326.0
  for i in range(mini(7,sim.log_entries.size())):
   var e: Dictionary=sim.log_entries[i]
   txt("DAY %02d" % e.day,484,y,10,TEAL);y=paragraph(e.text,565,y,538,14,INK,21)+22
   if y>767:break
 elif modal=="menu":
  txt("SHELTER OPERATIONS",484,239,11,GOLD);txt("Take a breath.",484,286,33)
  paragraph("Your shelter pauses while this menu is open. Progress is saved automatically every 20 seconds and on exit.",484,329,620,17)
  button(Rect2(484,417,632,50),"Save shelter",func():save_game(true),true)
  button(Rect2(484,482,632,50),"Load last save",func():load_game(true))
  button(Rect2(484,547,632,50),"How to play",func():modal="help")
  button(Rect2(484,612,632,50),"Start a new shelter",func():modal="restart")
  button(Rect2(484,677,632,50),"Return to shelter",func():modal="")
 elif modal=="restart":
  txt("A FRESH START",484,248,11,GOLD);txt("Begin a new shelter?",484,297,31)
  paragraph("This replaces the current shelter and its saved progress. Your Blender artwork and project files stay available.",484,350,615,18)
  button(Rect2(484,510,632,53),"Start new shelter",new_game,true)
  button(Rect2(484,582,632,53),"Keep this shelter",func():modal="menu")
 elif modal in ["victory","defeat"]:
  var won=modal=="victory"
  icon("Shelter",Vector2(800,269),GOLD if won else RED,2.8)
  centered("A NEW DAWN" if won else "THE LIGHTS WENT OUT",Rect2(476,335,648,60),34,GOLD if won else RED)
  paragraph("Your relay broke the silence. A rescue convoy is coming through the canyon. Shelter 07 has a future." if won else "The wasteland took this shelter. Next time, keep food and water flowing, fortify before raids, and repair the entrance.",494,440,602,20,INK,31)
  txt("Day %d  /  %d survivors  /  %d raids survived" % [sim.day(),sim.survivors,sim.raids_survived],494,578,17,TEAL)
  button(Rect2(494,635,612,52),"Start another shelter",func():modal="restart",true)
  button(Rect2(494,704,612,45),"Inspect shelter",func():modal="")

func select_room(index: int) -> void:
 selected=index
 if sim.rooms[index].kind=="":tab="Build"
 else:tab="Shelter"

func set_tab(value: String) -> void:
 tab=value
 if tab=="Build" and sim.rooms[selected].kind!="":
  for i in range(sim.rooms.size()):
   if sim.rooms[i].kind=="":selected=i;depth=clampi(int(i/2)-2,0,2);break

func build(kind: String) -> void:
 var result=sim.build_room(selected,kind);action(result)
 if result=="":tab="Shelter";notify_user("Construction started. Your new room will be ready in 14 seconds.")

func toggle_pause() -> void:
 speed=1 if speed==0 else 0

func action(error: String) -> void:
 if error!="":notify_user(error)
 queue_redraw()

func notify_user(message: String) -> void:
 toast=message;toast_left=4.5

func save_game(show_message: bool) -> String:
 if test_mode:return "Saving is disabled in test mode."
 var data=sim.snapshot();data["ui"]={"muted":muted}
 var file=FileAccess.open(save_path+".tmp",FileAccess.WRITE)
 if file==null:
  if show_message:notify_user("Could not write the save file.")
  return "Could not write the save file."
 file.store_string(JSON.stringify(data,"",true,true));file.close()
 var error=DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))
 if error!=OK:
  # Windows rename may not replace an existing file; preserve one backup.
  DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+".bak"))
  if FileAccess.file_exists(save_path):DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path+".bak"))
  error=DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))
 if show_message:notify_user("Shelter saved. Your people will be here." if error==OK else "Save could not be completed.")
 return "" if error==OK else "Save could not be completed."

func load_game(show_message: bool) -> String:
 if not FileAccess.file_exists(save_path):
  if show_message:notify_user("No saved shelter yet.")
  return "No saved shelter yet."
 var parser=JSON.new()
 var parse_error=parser.parse(FileAccess.get_file_as_string(save_path))
 var data=parser.data if parse_error==OK else null
 if not data is Dictionary or not sim.restore(data):
  if show_message:notify_user("That save is damaged. Your current shelter is still safe.")
  return "That save is damaged. Current shelter was preserved."
 muted=data.get("ui",{}).get("muted",false);captured_outcome=false
 if show_message:modal="";notify_user("Shelter restored.")
 return ""

func new_game() -> void:
 sim=Sim.new();selected=0;tab="Shelter";depth=0;speed=1;modal="";captured_outcome=false
 save_game(false);notify_user("A new beginning. Welcome to Shelter 07.")

func play_click() -> void:
 if muted:return
 var wave=AudioStreamWAV.new();wave.format=AudioStreamWAV.FORMAT_16_BITS;wave.mix_rate=22050
 var samples=PackedByteArray();samples.resize(2205*2)
 for i in range(2205):
  var v=int(sin(float(i)*TAU*660/22050)*exp(-float(i)/230.0)*4200)
  samples.encode_s16(i*2,v)
 wave.data=samples;audio_player.stream=wave;audio_player.play()

func _capture() -> void:
 await get_tree().process_frame
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://build/gameplay.png")
 print("CAPTURE_OK")
 get_tree().quit()

func _gallery() -> void:
 for view in ["Shelter","Build","People","Research","Map"]:
  set_tab(view);queue_redraw();await get_tree().process_frame;await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://build/"+view.to_lower()+".png")
 modal="help";queue_redraw();await get_tree().process_frame;await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://build/help.png")
 print("GALLERY_OK");get_tree().quit()

func _smoke() -> void:
 await get_tree().process_frame
 await get_tree().process_frame
 await _test_click(Vector2(750,809))
 if tab!="Build" or selected!=5:push_error("Room click did not open construction");get_tree().quit(1);return
 await _test_click(Vector2(1327,543))
 if sim.rooms[5].kind!="lab" or tab!="Shelter":push_error("Build button did not construct a lab");get_tree().quit(1);return
 sim.tick(15);queue_redraw();await get_tree().process_frame;await get_tree().process_frame
 await _test_click(Vector2(1478,596))
 if sim.rooms[5].workers!=1:push_error("Staffing button did not assign a survivor");get_tree().quit(1);return
 await _test_click(Vector2(794,961))
 if tab!="Research":push_error("Navigation click did not open research");get_tree().quit(1);return
 await _test_click(Vector2(1330,573))
 if sim.research.get("key", "")!="efficiency":push_error("Research click did not start a project");get_tree().quit(1);return
 sim.tick(30)
 if "efficiency" not in sim.unlocked:push_error("Research failed after input sequence");get_tree().quit(1);return
 print("INPUT_SMOKE_OK: room selection, construction, staffing, navigation, research")
 for view in ["Shelter","Build","People","Research","Map"]:
  set_tab(view);queue_redraw();await get_tree().process_frame;await get_tree().process_frame
 for view in ["help","journal","menu","restart","victory","defeat"]:
  modal=view;queue_redraw();await get_tree().process_frame;await get_tree().process_frame
 modal="";selected=5;set_tab("Research")
 for view in ["Shelter","Build","People","Research","Map"]:
  tab=view;queue_redraw();await get_tree().process_frame;await get_tree().process_frame
 print("UI_SMOKE_OK")
 get_tree().quit()

func _test_click(point: Vector2) -> void:
 var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=point
 get_viewport().push_input(event,true)
 event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false;event.position=point
 get_viewport().push_input(event,true)
 queue_redraw();await get_tree().process_frame;await get_tree().process_frame

func _save_smoke() -> void:
 await get_tree().process_frame
 save_path="res://build/test_save.json";test_mode=false;speed=0
 sim.stock.scrap=247;save_game(false)
 sim.stock.scrap=51;load_game(false)
 if sim.stock.scrap!=247:push_error("Disk save/load failed");get_tree().quit(1);return
 sim.stock.scrap=318;save_game(false);sim.stock.scrap=17;load_game(false)
 if sim.stock.scrap!=318:push_error("Save replacement failed");get_tree().quit(1);return
 var file=FileAccess.open(save_path,FileAccess.WRITE);file.store_string("{broken");file.close()
 load_game(false)
 if sim.stock.scrap!=318:push_error("Corrupt save changed live state");get_tree().quit(1);return
 test_mode=true;print("SAVE_IO_OK: roundtrip, replacement, corrupt-save recovery")
 get_tree().quit()

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
var last_depth = 0
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
var dragging_char_id = -1
var drag_candidate_id = -1
var drag_start_pos = Vector2.ZERO
var selected_char_id = -1
var perk_modal_char_id = -1
var shelter_speech_timer = 15.0
var char_render_pos: Dictionary = {}
var floating_texts: Array = []
var screen_shake = 0.0
var particles: Array = []
var elevator_y = 365.0
var rng = RandomNumberGenerator.new()

func _ready() -> void:
 font = load("res://assets/fonts/Inter.woff2")
 if font==null:font=ThemeDB.fallback_font
 for key in ["surface","command","power","water","food","dorm","lab","medbay","workshop","security","empty","storage","earth"]:
  if ResourceLoader.exists("res://assets/renders/"+key+".png"):
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
 if screen_shake>0:screen_shake=maxf(0,screen_shake-dt*6.0)
 _update_characters(dt)
 for i in range(floating_texts.size()-1,-1,-1):
  var ft=floating_texts[i]
  ft.y-=dt*26.0;ft.time-=dt
  if ft.time<=0:floating_texts.remove_at(i)
 _update_particles(dt)
 if sim.active_encounter.get("pending", false) and modal=="":
  modal="encounter";play_sound("alarm")
 ui_refresh+=dt
 if ui_refresh>=1.0/30:ui_refresh=0;queue_redraw()

func sync_outcome() -> void:
 if sim.outcome!="" and not captured_outcome:
  captured_outcome=true;modal=sim.outcome;save_game(false)

func get_character_pos(c: Dictionary) -> Vector2:
 if c.get("on_expedition", false):
  return Vector2(140 + int(c.id) * 38, 220)
 var r_idx = int(c.room)
 if r_idx == -1:
  var home = 4 if sim.rooms[4].kind != "" else 0
  var h_row = int(home / 2) - depth
  if h_row >= 0 and h_row < 3:
   var h_col = home % 2
   return Vector2(40 + h_col * 510 + 260 + (int(c.id) % 3) * 55, 280 + h_row * 215 + 160)
  return Vector2(-1000, -1000)
 var floor_idx = int(r_idx / 2)
 var row = floor_idx - depth
 if row >= 0 and row < 3:
  var col = r_idx % 2
  var slot = 0
  for other in sim.characters:
   if other.id == c.id: break
   if other.room == r_idx: slot += 1
  return Vector2(40 + col * 510 + 95 + slot * 80, 280 + row * 215 + 160)
 return Vector2(-1000, -1000)

func _get_character_at(pos: Vector2) -> Dictionary:
 for c in sim.characters:
  var p = char_render_pos.get(c.id, Vector2(-1000, -1000))
  if p.x > 0 and p.distance_to(pos) < 26:
   return c
 if tab == "People":
  var x = 1135.0
  for i in range(mini(sim.characters.size(), 6)):
   var card_r = Rect2(x + 22, 480 + i * 58, 380, 52)
   if card_r.has_point(pos):
    return sim.characters[i]
 return {}

func _get_room_at(pos: Vector2) -> int:
 for row in range(3):
  var y = 280 + row * 215
  for col in range(2):
   var r_rect = Rect2(40 + col * 510, y, 490, 195)
   if r_rect.has_point(pos):
    return (row + depth) * 2 + col
 return -1

func _update_characters(dt: float) -> void:
 shelter_speech_timer = maxf(0.0, shelter_speech_timer - dt)
 if depth != last_depth:
  last_depth = depth
  for c in sim.characters:
   char_render_pos[c.id] = get_character_pos(c)
 var visible_chars: Array = []
 for c in sim.characters:
  var target_pos = get_character_pos(c)
  if target_pos.x > 0:
   visible_chars.append(c)
   if not c.id in char_render_pos or char_render_pos[c.id].x <= 0:
    char_render_pos[c.id] = target_pos
   else:
    var cur: Vector2 = char_render_pos[c.id]
    if absf(cur.y - target_pos.y) > 10.0:
     if cur.x < 1050.0:
      cur.x = move_toward(cur.x, 1060.0, dt * 140.0 * maxf(1, speed))
     else:
      cur.y = target_pos.y
      cur.x = 1050.0
    else:
     cur.x = move_toward(cur.x, target_pos.x, dt * 140.0 * maxf(1, speed))
     cur.y = target_pos.y
    char_render_pos[c.id] = cur
  else:
   char_render_pos[c.id] = Vector2(-1000, -1000)
 if shelter_speech_timer <= 0 and visible_chars.size() > 0 and speed > 0:
  var speaker: Dictionary = visible_chars[rng.randi_range(0, visible_chars.size() - 1)]
  if speaker.get("speech", "") == "":
   var pool = ["Grid humming along.", "Filtered water tastes fine today.", "Checking atmospheric seals.", "Good to have a secure roof."]
   if sim.stock.water < 35: pool = ["Water reserves are looking thin."]
   elif sim.stock.food < 30: pool = ["Rations running low."]
   elif sim.stock.energy < 25: pool = ["Conserving generator power."]
   speaker.speech = pool[rng.randi_range(0, pool.size() - 1)]
   speaker.speech_time = 4.0
   shelter_speech_timer = rng.randf_range(25.0, 40.0)

func _update_particles(dt: float) -> void:
 for i in range(particles.size()-1,-1,-1):
  var p=particles[i]
  p.x+=p.vx*dt;p.y+=p.vy*dt;p.life-=dt
  if p.life<=0:particles.remove_at(i)
 # Spawn sparks or fire in rooms with emergencies
 for em in sim.emergencies:
  var r_idx=em.room
  var row=int(r_idx/2)-depth
  if row>=0 and row<3:
   var col=r_idx%2
   var rx=42+col*505;var ry=365+row*183
   if em.kind=="fire" and particles.size()<60:
    particles.append({"x":rx+rng.randf_range(30,460),"y":ry+155,"vx":rng.randf_range(-12,12),"vy":rng.randf_range(-35,-70),"life":rng.randf_range(0.4,0.9),"col":Color(1,.55,.1,.8)})
   elif em.kind=="malfunction" and particles.size()<40:
    particles.append({"x":rx+rng.randf_range(50,440),"y":ry+rng.randf_range(40,150),"vx":rng.randf_range(-30,30),"vy":rng.randf_range(-30,20),"life":rng.randf_range(0.2,0.45),"col":Color(.6,.9,1,.9)})

func spawn_floating_text(text: String, pos: Vector2, col: Color=GOLD) -> void:
 floating_texts.append({"text":text,"x":pos.x,"y":pos.y,"time":1.3,"color":col})

func play_sound(type: String="click") -> void:
 if muted:return
 var wave=AudioStreamWAV.new();wave.format=AudioStreamWAV.FORMAT_16_BITS;wave.mix_rate=22050
 var duration_samples=2205;var samples=PackedByteArray()
 match type:
  "assign":
   duration_samples=3300;samples.resize(duration_samples*2)
   for i in range(duration_samples):
    var t=float(i)/22050.0;var f=440.0+t*500.0
    samples.encode_s16(i*2,int(sin(float(i)*TAU*f/22050)*exp(-t*8.0)*4200))
  "coin":
   duration_samples=3500;samples.resize(duration_samples*2)
   for i in range(duration_samples):
    var t=float(i)/22050.0
    var v=int((sin(float(i)*TAU*880/22050)*.6+sin(float(i)*TAU*1320/22050)*.4)*exp(-t*9.0)*4400)
    samples.encode_s16(i*2,v)
  "alarm":
   duration_samples=5500;samples.resize(duration_samples*2)
   for i in range(duration_samples):
    var t=float(i)/22050.0;var f=330.0 if int(t*10)%2==0 else 240.0
    samples.encode_s16(i*2,int(sin(float(i)*TAU*f/22050)*4000))
  "levelup":
   duration_samples=5500;samples.resize(duration_samples*2)
   for i in range(duration_samples):
    var t=float(i)/22050.0;var f=523.25 if t<.08 else (659.25 if t<.16 else 783.99)
    samples.encode_s16(i*2,int(sin(float(i)*TAU*f/22050)*exp(-fmod(t,.08)*10.0)*4400))
  "ability":
   duration_samples=3500;samples.resize(duration_samples*2)
   for i in range(duration_samples):
    var t=float(i)/22050.0;var f=750.0-t*400.0
    samples.encode_s16(i*2,int(sin(float(i)*TAU*f/22050)*exp(-t*6.0)*4200))
  _:
   samples.resize(duration_samples*2)
   for i in range(duration_samples):
    samples.encode_s16(i*2,int(sin(float(i)*TAU*660/22050)*exp(-float(i)/230.0)*4200))
 wave.data=samples;audio_player.stream=wave;audio_player.play()

func play_click() -> void:
 play_sound("click")

func _input(event: InputEvent) -> void:
 if event is InputEventMouseMotion:
  mouse=event.position
  if drag_candidate_id!=-1 and dragging_char_id==-1:
   if mouse.distance_to(drag_start_pos)>8.0:
    dragging_char_id=drag_candidate_id
    play_sound("click")
  var hover=false
  for hit in hitboxes:
   if hit.rect.has_point(mouse):hover=true;break
  if dragging_char_id!=-1:hover=true
  mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if hover else Control.CURSOR_ARROW
 elif event is InputEventMouseButton:
  mouse=event.position
  if event.pressed:
   if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and mouse.x<1140 and modal=="":depth=mini(2,depth+1)
   elif event.button_index==MOUSE_BUTTON_WHEEL_UP and mouse.x<1140 and modal=="":depth=maxi(0,depth-1)
   elif event.button_index==MOUSE_BUTTON_LEFT:
    var clicked_char=_get_character_at(mouse)
    if not clicked_char.is_empty() and modal=="":
     drag_candidate_id=int(clicked_char.id);drag_start_pos=mouse
    else:
     drag_candidate_id=-1
    for i in range(hitboxes.size()-1,-1,-1):
     if hitboxes[i].rect.has_point(mouse):
      var callback: Callable=hitboxes[i].action
      callback.call();play_click();break
  else:
   if event.button_index==MOUSE_BUTTON_LEFT:
    if dragging_char_id!=-1:
     var target_room=_get_room_at(mouse)
     if target_room!=-1:
      var res=sim.assign_character(dragging_char_id, target_room)
      if res=="":
       spawn_floating_text("Assigned!", mouse, TEAL);play_sound("assign")
      else:
       action(res)
     elif mouse.x<1140 and mouse.y>120:
      sim.assign_character(dragging_char_id, -1)
      spawn_floating_text("Unassigned", mouse, MUTED);play_sound("click")
    elif drag_candidate_id!=-1 and mouse.distance_to(drag_start_pos)<=8.0:
     selected_char_id=drag_candidate_id
     for c in sim.characters:
      if c.id==drag_candidate_id and c.room!=-1:
       select_room(c.room);break
    drag_candidate_id=-1;dragging_char_id=-1
   queue_redraw()
 elif event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_ESCAPE:
   if modal=="encounter":sim.resolve_encounter(1)
   modal="" if modal!="" else "help"
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
  "can","food":
   draw_rect(Rect2(p.x-7*s,p.y-8*s,14*s,16*s),Color("d95338"),true)
   draw_rect(Rect2(p.x-7*s,p.y-4*s,14*s,8*s),Color("f4eedb"),true)
   draw_line(Vector2(p.x-7*s,p.y-8*s),Vector2(p.x+7*s,p.y-8*s),Color("cad5e2"),2*s,true)
   draw_line(Vector2(p.x-7*s,p.y+8*s),Vector2(p.x+7*s,p.y+8*s),Color("cad5e2"),2*s,true)
  "bottle","water":
   draw_rect(Rect2(p.x-2.5*s,p.y-11*s,5*s,3*s),Color("94c5e8"),true)
   draw_rect(Rect2(p.x-5.5*s,p.y-7*s,11*s,17*s),Color("38bdf8"),true)
   draw_line(Vector2(p.x-5*s,p.y-1*s),Vector2(p.x+5*s,p.y-1*s),Color("1e293b"),1.5*s,true)
   draw_line(Vector2(p.x-5*s,p.y+4*s),Vector2(p.x+5*s,p.y+4*s),Color("1e293b"),1.5*s,true)
  "scrap","Build":
   draw_colored_polygon(PackedVector2Array([Vector2(p.x-8*s,p.y+8*s),Vector2(p.x-4*s,p.y-4*s),Vector2(p.x+3*s,p.y-8*s),Vector2(p.x+9*s,p.y+8*s)]),Color("94a3b8"))
   draw_line(Vector2(p.x-7*s,p.y+2*s),Vector2(p.x+6*s,p.y-3*s),Color("475569"),2*s,true)
   draw_line(Vector2(p.x-2*s,p.y-2*s),Vector2(p.x+8*s,p.y+4*s),Color("334155"),1.5*s,true)
  "gear","energy","power":
   draw_arc(p,6*s,0,TAU,16,Color("cbd5e1"),3*s,true)
   draw_circle(p,2.5*s,Color("0e161a"),true,-1,true)
   for n in range(6):
    var a=n*TAU/6.0
    draw_line(p+Vector2(cos(a)*4.5*s,sin(a)*4.5*s),p+Vector2(cos(a)*9*s,sin(a)*9*s),Color("cbd5e1"),2.5*s,true)
  "cell","credits":
   draw_rect(Rect2(p.x-5*s,p.y-9*s,10*s,18*s),Color("10b981"),true)
   draw_rect(Rect2(p.x-2*s,p.y-11*s,4*s,2*s),Color("cbd5e1"),true)
   draw_line(Vector2(p.x-4*s,p.y-3*s),Vector2(p.x+4*s,p.y-3*s),Color("064e3b"),1.5*s,true)
   draw_line(Vector2(p.x-4*s,p.y+3*s),Vector2(p.x+4*s,p.y+3*s),Color("064e3b"),1.5*s,true)
  "power_switch":
   draw_arc(p+Vector2(0,1)*s,7*s,PI*0.75,PI*2.25,16,Color("10b981"),2*s,true)
   draw_line(p+Vector2(0,-7)*s,p+Vector2(0,1)*s,Color("10b981"),2*s,true)
  "heart":
   draw_circle(p+Vector2(-3.5,-2)*s,3.8*s,RED,true,-1,true)
   draw_circle(p+Vector2(3.5,-2)*s,3.8*s,RED,true,-1,true)
   draw_colored_polygon(PackedVector2Array([Vector2(p.x-7.2*s,p.y-1*s),Vector2(p.x+7.2*s,p.y-1*s),Vector2(p.x,p.y+8*s)]),RED)
  "shield":
   draw_colored_polygon(PackedVector2Array([Vector2(p.x-7*s,p.y-7*s),Vector2(p.x+7*s,p.y-7*s),Vector2(p.x+7*s,p.y+1*s),Vector2(p.x,p.y+8*s),Vector2(p.x-7*s,p.y+1*s)]),color)
   draw_line(Vector2(p.x,p.y-6*s),Vector2(p.x,p.y+6*s),Color("1e293b"),1.5*s,true)
  "raid","crosshair":
   draw_arc(p,7*s,0,TAU,16,color,1.5*s,true)
   draw_line(p+Vector2(-9*s,0),p+Vector2(9*s,0),color,1.5*s,true)
   draw_line(p+Vector2(0,-9*s),p+Vector2(0,9*s),color,1.5*s,true)
   draw_circle(p,2*s,color,true,-1,true)
  "survivors","People","dorm":
   draw_circle(p+Vector2(-4,-4)*s,3.5*s,color,true,-1,true)
   draw_circle(p+Vector2(4,-2)*s,3.0*s,color,true,-1,true)
   draw_arc(p+Vector2(-4,8)*s,5.5*s,PI,TAU,12,color,3.5*s,true)
   draw_arc(p+Vector2(4,8)*s,4.5*s,PI,TAU,12,color,3.0*s,true)
  "backpack","Expedition","Map":
   draw_rect(Rect2(p.x-6*s,p.y-6*s,12*s,14*s),color,true)
   draw_rect(Rect2(p.x-4*s,p.y-9*s,8*s,3*s),color.lightened(0.2),true)
   draw_line(Vector2(p.x-6*s,p.y+1*s),Vector2(p.x+6*s,p.y+1*s),Color("1e293b"),1.5*s,true)
  "book","Research","lab":
   draw_colored_polygon(PackedVector2Array([Vector2(p.x-8*s,p.y-5*s),Vector2(p.x,p.y-2*s),Vector2(p.x,p.y+7*s),Vector2(p.x-8*s,p.y+4*s)]),color)
   draw_colored_polygon(PackedVector2Array([Vector2(p.x+8*s,p.y-5*s),Vector2(p.x,p.y-2*s),Vector2(p.x,p.y+7*s),Vector2(p.x+8*s,p.y+4*s)]),color)
  "log","Journal","Log":
   draw_rect(Rect2(p.x-5*s,p.y-7*s,10*s,15*s),color,true)
   draw_rect(Rect2(p.x-3*s,p.y-9*s,6*s,2*s),Color("cbd5e1"),true)
   draw_line(Vector2(p.x-3*s,p.y-2*s),Vector2(p.x+3*s,p.y-2*s),Color("1e293b"),1.5*s,true)
   draw_line(Vector2(p.x-3*s,p.y+2*s),Vector2(p.x+3*s,p.y+2*s),Color("1e293b"),1.5*s,true)
  "shelter","Shelter","home":
   draw_colored_polygon(PackedVector2Array([Vector2(p.x-8*s,p.y+6*s),Vector2(p.x-8*s,p.y-1*s),Vector2(p.x,p.y-8*s),Vector2(p.x+8*s,p.y-1*s),Vector2(p.x+8*s,p.y+6*s)]),color)
   draw_rect(Rect2(p.x-2.5*s,p.y,5*s,6*s),Color("1e293b"),true)
  _:
   draw_arc(p,8*s,0,TAU,16,color,2*s,true)

func _draw_character(c: Dictionary, pos: Vector2, is_working: bool=false, is_panicking: bool=false) -> void:
 var x=pos.x;var y=pos.y
 var bob=sin(clock_time*3.5+int(c.id))*1.5 if is_working else sin(clock_time*2.0+int(c.id))*0.8
 if is_panicking:bob+=sin(clock_time*14.0)*1.8
 y+=bob
 draw_circle(Vector2(x,pos.y+2),8.0,Color(0,0,0,0.35))
 draw_line(Vector2(x-3,y-8),Vector2(x-3,y),Color("18242a"),3.0,true)
 draw_line(Vector2(x+3,y-8),Vector2(x+3,y),Color("18242a"),3.0,true)
 var trait_str=c.get("trait","")
 var suit_col=Color("76bf86") if trait_str=="Green Thumb" else (GOLD if trait_str=="Engineer" else (TEAL if trait_str=="Optimist" else Color("38525f")))
 box(Rect2(x-7,y-22,14,15),suit_col,Color("1e2f37"),4)
 draw_line(Vector2(x-5,y-14),Vector2(x+5,y-14),Color("182329"),1.5)
 draw_circle(Vector2(x,y-28),6.5,Color("dfc59e"),true,-1,true)
 var hair_col=Color("8c6543") if int(c.id)%2==0 else Color("322b27")
 draw_arc(Vector2(x,y-29),6.5,PI,TAU,16,hair_col,2.2,true)
 draw_line(Vector2(x-3,y-28),Vector2(x+3,y-28),TEAL,1.8,true)
 var has_speech=c.get("speech","")!=""
 var is_sel=selected_char_id==int(c.id)
 var is_hov=mouse.distance_to(pos)<22
 if has_speech:
  var sp_text=str(c.speech)
  var sp_w=font.get_string_size(sp_text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+16
  var bubble_x=clampf(x-sp_w/2.0,36.0,1050.0-sp_w)
  var bubble_y=y-54.0
  box(Rect2(bubble_x,bubble_y,sp_w,20),Color(.06,.12,.15,.95),TEAL,4)
  draw_polygon(PackedVector2Array([Vector2(x-3,bubble_y+20),Vector2(x+3,bubble_y+20),Vector2(x,bubble_y+23)]),PackedColorArray([TEAL,TEAL,TEAL]))
  centered(sp_text,Rect2(bubble_x,bubble_y,sp_w,20),11,INK)
 if is_hov or is_sel:
  draw_arc(Vector2(x,pos.y+2),10.5,0,TAU,20,GOLD if is_sel else TEAL,1.5,true)
  var label="%s · Lv.%d (%s)" % [c.name,c.level,c.get("trait","Survivor")]
  var lw=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+14
  var ly=y-74.0 if has_speech else y-48.0
  box(Rect2(x-lw/2,ly,lw,18),Color("0d181e"),TEAL,4)
  centered(label,Rect2(x-lw/2,ly,lw,18),11,INK)

func _draw_dragged_character() -> void:
 var c=null
 for char_obj in sim.characters:
  if char_obj.id==dragging_char_id:c=char_obj;break
 if c==null:return
 var dp=mouse+Vector2(16,-18)
 box(Rect2(dp.x,dp.y,142,36),Color("142830"),TEAL,7,2)
 draw_circle(Vector2(dp.x+18,dp.y+18),10,Color("2a434c"),true,-1,true)
 centered(c.name.left(1),Rect2(dp.x+8,dp.y+8,20,20),14,TEAL)
 txt(c.name,dp.x+36,dp.y+16,13,INK)
 txt("LV.%d · %s" % [c.level,c.get("trait","")],dp.x+36,dp.y+30,9,GOLD)

func _draw() -> void:
 if font==null:return
 hitboxes.clear();hover_tip=""
 if screen_shake>0:
  draw_set_transform(Vector2(rng.randf_range(-screen_shake,screen_shake),rng.randf_range(-screen_shake,screen_shake)),0.0,Vector2.ONE)
 draw_rect(Rect2(-10,-10,1620,1020),BG)
 draw_header();draw_bunker();draw_sidebar();draw_footer()
 if modal!="":draw_modal()
 if toast_left>0:
  var w=minf(1000,font.get_string_size(toast,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+46)
  box(Rect2(800-w/2,865,w,48),Color("294740"),TEAL,8);centered(toast,Rect2(800-w/2,865,w,48),17)
 for ft in floating_texts:
  var alpha=clampf(ft.time/0.5,0.0,1.0)
  txt(ft.text,ft.x,ft.y,16,Color(ft.color.r,ft.color.g,ft.color.b,alpha))
 if dragging_char_id!=-1:
  _draw_dragged_character()
 if hover_tip!="" and modal=="":
  var w=minf(510,font.get_string_size(hover_tip,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+28)
  var x=clampf(mouse.x-w/2,14,1586-w);var y=minf(mouse.y+22,964)
  box(Rect2(x,y,w,30),Color("0d181e"),LINE,5);centered(hover_tip,Rect2(x,y,w,30),14,MUTED)
 if screen_shake>0:
  draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func draw_header() -> void:
 box(Rect2(0,0,1600,54),Color("0d1519"),Color("1e2e38"),0,1)
 txt("NEW DAWN",20,32,22,Color("f1f5f9"))
 txt("ALTERNATE DRAFT",21,46,9,Color("38bdf8"))
 var net=sim.rates()
 var res_data=[
  {"name":"food","icon":"can","count":int(sim.stock.food),"rate":net.get("food",0.0),"color":Color("e05338")},
  {"name":"water","icon":"bottle","count":int(sim.stock.water),"rate":net.get("water",0.0),"color":Color("38bdf8")},
  {"name":"scrap","icon":"scrap","count":int(sim.stock.scrap),"rate":net.get("scrap",0.0),"color":Color("94a3b8")},
  {"name":"energy","icon":"gear","count":int(sim.stock.energy),"rate":net.get("energy",0.0),"color":Color("cbd5e1")},
  {"name":"credits","icon":"cell","count":int(sim.stock.credits),"rate":0.0,"color":Color("10b981")}
 ]
 for i in range(res_data.size()):
  var item=res_data[i]
  var rx=285+i*170
  box(Rect2(rx,8,155,38),Color("121f26"),Color("253842"),6)
  icon(item.icon,Vector2(rx+22,27),item.color,1.0)
  txt(str(item.count),rx+42,26,17,Color("f1f5f9"))
  var rate_str="+%.0f/h" % (item.rate*60.0) if item.name!="credits" else "+2/h"
  if item.rate<0:rate_str="%.0f/h" % (item.rate*60.0)
  txt(rate_str,rx+42,39,10,TEAL if item.rate>=0 else RED)

 var power_pct=int(clampf(float(sim.stock.energy)/maxf(1.0,float(sim.max_stock("energy")))*100.0,0,100))
 icon("power_switch",Vector2(1170,27),Color("10b981"),1.0)
 txt("%d%%" % power_pct,1185,32,15,Color("f1f5f9"))
 draw_circle(Vector2(1230,27),3.5,Color("10b981"),true,-1,true)

 button(Rect2(1255,10,36,34),"Ⅱ" if speed>0 else "▶",toggle_pause,false,false,"Pause / resume · Space",16)
 for n in range(3):
  var val=[1,2,4][n]
  button(Rect2(1296+n*36,10,33,34),str(val)+"×",func():speed=val,speed==val,false,"Game speed · "+str(n+1),13)

 button(Rect2(1412,10,85,34),"≡ MENU",func():modal="menu",false,false,"Operations menu",13)
 button(Rect2(1504,10,34,34),"?",func():modal="help",false,false,"How to play",16)

func draw_bunker() -> void:
 if "earth" in textures:
  draw_texture_rect(textures.earth,Rect2(0,240,1600,696),false)
 else:
  draw_rect(Rect2(0,240,1600,696),Color("151a1d"))

 if "surface" in textures:
  draw_texture_rect(textures.surface,Rect2(0,54,1600,216),false)

 box(Rect2(935,248,160,26),Color(.05,.08,.09,.9),Color.TRANSPARENT,5)
 txt("DEPTH  %02d–%02d" % [depth+1,depth+3],945,265,11,MUTED)
 button(Rect2(1040,248,26,26),"↑",func():depth=maxi(0,depth-1),false,depth==0,"Scroll up",14)
 button(Rect2(1068,248,26,26),"↓",func():depth=mini(2,depth+1),false,depth==2,"Scroll down",14)

 for row in range(3):
  var y=280+row*215
  for col in range(2):
   var index=(row+depth)*2+col
   draw_room(index,Rect2(40+col*510,y,490,195))
  box(Rect2(1055,y,52,195),Color("131c1e"),Color("384950"),6,2)
  box(Rect2(1062,y+12,38,168),Color("222a2a"),Color("414a44"),3)
  draw_line(Vector2(1081,y+13),Vector2(1081,y+178),Color("0a1519"),2)
  for ex in [1066,1095]:
   draw_line(Vector2(ex,y+24),Vector2(ex,y+165),Color(.96,.52,.16,.15),8,true)
   draw_line(Vector2(ex,y+24),Vector2(ex,y+165),GOLD,2,true)
  box(Rect2(1075,y+85,12,29),Color("0f191b"),Color.TRANSPARENT,2)
  draw_circle(Vector2(1081,y+94),2,TEAL,true,-1,true)
  txt("%02d" % (row+depth+1),1073,y+188,9,MUTED)

 for p in particles:
  draw_circle(Vector2(p.x,p.y),2.2,p.col,true,-1,true)

 for c in sim.characters:
  if c.id==dragging_char_id:continue
  var p=char_render_pos.get(c.id,Vector2(-1000,-1000))
  if p.x>30 and p.x<1120 and p.y>120 and p.y<930:
   var is_working=c.get("state","")=="working"
   var is_panicking=false
   for em in sim.emergencies:
    if em.room==c.room:is_panicking=true;break
   _draw_character(c,p,is_working,is_panicking)

func draw_room(index: int, r: Rect2) -> void:
 var room: Dictionary=sim.rooms[index];var kind: String=room.kind
 var over=r.has_point(mouse);var active=selected==index

 var frame_col=Color("22d3ee") if active else (Color("4b6470") if over else Color("2a3c46"))
 box(r.grow(3),Color("10191c"),frame_col,6,3 if active else 2)

 var tex_key="empty" if kind=="" else kind
 if tex_key in textures:
  draw_texture_rect(textures[tex_key],r,false)

 var room_title="EXCAVATED CHAMBER"
 if kind in Sim.ROOM_TYPES:
  room_title=Sim.ROOM_TYPES[kind].name.to_upper()
  if kind=="food":room_title="GREENHOUSE"
  elif kind=="water":room_title="WATER PURIFIER"

 var badge_w=font.get_string_size(room_title,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+22
 var badge_r=Rect2(r.position.x+(r.size.x-badge_w)/2,r.position.y-10,badge_w,20)
 box(badge_r,Color("0a1418"),Color("22d3ee") if active else Color("283d47"),4)
 centered(room_title,badge_r,11,Color("22d3ee") if active else INK)

 if dragging_char_id!=-1 and over:
  if kind!="" and room.build_left<=0:
   box(r.grow(4),Color.TRANSPARENT,TEAL,8,3)
   box(Rect2(r.position.x+10,r.position.y+10,150,26),Color(.05,.20,.18,.85),TEAL,6)
   txt("DROP TO ASSIGN",r.position.x+22,r.position.y+27,12,INK)
  elif kind=="":
   box(r.grow(4),Color.TRANSPARENT,RED,8,2)

 var em_kind=""
 for em in sim.emergencies:
  if em.room==index:em_kind=em.kind;break
 if em_kind!="":
  var pulse=(sin(clock_time*8.0)+1.0)*0.5
  box(r.grow(4),Color(.5,.1,.05,.20*pulse),RED,8,3)
  var em_r=Rect2(r.position.x+10,r.end.y-32,185,24)
  box(em_r,Color("52140e"),RED,5)
  txt("⚠ %s ♦ %s" % [room_title,em_kind.to_upper()],r.position.x+16,r.end.y-16,10,INK)
  button(Rect2(r.position.x+202,r.end.y-32,85,24),"Suppress",func():action(sim.suppress_emergency(index));play_sound("click");spawn_floating_text("Extinguished!",mouse,TEAL),false,false,"Extinguish emergency",11)

 var oc=sim.abilities.get("overclock",{})
 if float(oc.get("timer",0.0))>0 and int(oc.get("room",-1))==index:
  box(Rect2(r.position.x+10,r.position.y+16,110,22),Color("3d3110"),GOLD,5)
  txt("⚡ 200% BOOST",r.position.x+18,r.position.y+31,11,GOLD)

 if kind=="":
  draw_rect(r,Color(.03,.07,.09,.40))
  centered("+ BUILD A NEW ROOM",Rect2(r.position.x,r.position.y+115,r.size.x,26),13,TEAL)
 elif room.build_left>0:
  draw_rect(r,Color(.08,.07,.03,.45))
  centered("UNDER CONSTRUCTION",Rect2(r.position.x,r.position.y+70,r.size.x,25),15,GOLD)
  meter(r.position.x+85,r.position.y+120,r.size.x-170,1-room.build_left/room.build_total,GOLD,4)
 elif room.workers>0 and Sim.ROOM_TYPES[kind].output!="":
  var pulse=.50+sin(clock_time*2+index)*.18
  box(Rect2(r.end.x-99,r.position.y+12,86,22),Color(.03,.08,.09,.90),Color.TRANSPARENT,11)
  draw_circle(Vector2(r.end.x-86,r.position.y+23),2.5,Color(Color(Sim.ROOM_TYPES[kind].color),pulse+.25),true,-1,true)
  txt("+%.2f/s" % sim.gross_output(index),r.end.x-77,r.position.y+27,11,Color(Sim.ROOM_TYPES[kind].color))

 hitboxes.append({"rect":r,"action":func():select_room(index)})

func draw_sidebar() -> void:
 var x=1142.0;var w=438.0
 box(Rect2(x,60,w,208),Color("0b1215"),Color("25353d"),8,2)
 icon("survivors",Vector2(x+30,88),Color("e2e8f0"),1.1)
 txt("%d/12" % sim.survivors,x+58,91,20,INK)
 txt("PEOPLE",x+58,106,9,MUTED)
 icon("heart",Vector2(x+30,132),RED,1.1)
 var morale_net="-2" if sim.morale<50 else "+1"
 txt(morale_net,x+56,137,15,INK)
 meter(x+95,130,230,sim.morale/100.0,Color("22d3ee"),7)
 txt("MORALE",x+335,137,9,MUTED)
 txt("%d%%" % int(sim.morale),x+386,137,11,Color("22d3ee"))
 icon("shield",Vector2(x+30,172),Color("94a3b8"),1.1)
 var int_net="-4" if sim.integrity<100 else "0"
 txt(int_net,x+56,177,15,INK)
 meter(x+95,170,230,sim.integrity/100.0,Color("22d3ee") if sim.integrity>40 else RED,7)
 txt("INTEGRITY",x+335,177,9,MUTED)
 txt("%d%%" % int(sim.integrity),x+386,177,11,Color("22d3ee") if sim.integrity>40 else RED)
 icon("raid",Vector2(x+30,218),Color("94a3b8"),1.1)
 var raid_txt="RAID IN %ds" % ceili(sim.raid_in)
 txt(raid_txt,x+58,224,15,RED if sim.raid_in<20 else INK)
 if sim.braced:txt("FORTIFIED",x+240,224,11,TEAL)
 if sim.missions.size()>0:
  var m: Dictionary=sim.missions[0]
  var can_claim=float(m.current)>=float(m.target) and not bool(m.claimed)
  if can_claim:
   button(Rect2(x+18,238,w-36,26),"★ CLAIM MISSION: "+m.title,func():action(sim.claim_mission(m.id));play_sound("coin");spawn_floating_text("+%d Scrap" % m.scrap,mouse,GOLD),true,false,"Claim reward",11)

 var tab_border=Color("22d3ee") if tab=="Shelter" else Color("2a3f47")
 box(Rect2(x,276,w,646),Color("0a1215"),tab_border,8,2)
 match tab:
  "Build":draw_build(x)
  "People":draw_people(x)
  "Research":draw_research(x)
  "Map":draw_map(x)
  _:draw_inspector(x)

func draw_inspector(x: float) -> void:
 var r: Dictionary=sim.rooms[selected];var kind: String=r.kind
 if kind=="":
  txt("EXCAVATED CHAMBER",x+24,308,18,Color("22d3ee"))
  txt("EXPANSION SITE",x+24,328,10,MUTED)
  paragraph("An unassigned subterranean chamber ready for construction. Build a room to give your survivors a better tomorrow.",x+24,355,390,14,MUTED,20)
  draw_texture_rect(textures.empty,Rect2(x+24,430,390,140),false)
  button(Rect2(x+24,590,390,44),"Choose a room  →",func():set_tab("Build"),true)
  return
 var info: Dictionary=Sim.ROOM_TYPES[kind]
 var room_title=info.name.to_upper()
 if kind=="food":room_title="GREENHOUSE"
 elif kind=="water":room_title="WATER PURIFIER"
 txt(room_title,x+24,308,19,Color("22d3ee"))
 txt("LEVEL %d MODULE" % r.level,x+24,328,10,MUTED)
 draw_line(Vector2(x+24,342),Vector2(x+414,342),Color("1e2c33"),1)

 txt("%d STAFF" % r.workers,x+24,368,16,INK)
 txt("MAX 3 WORKERS",x+24,386,10,MUTED)
 for n in range(3):
  var px=x+24+n*48
  box(Rect2(px,402,40,40),Color("122126") if n<r.workers else Color("0e171a"),Color("22d3ee") if n<r.workers else Color("223038"),6)
  icon("survivors",Vector2(px+20,422),Color("22d3ee") if n<r.workers else Color("3a4c54"),0.75)
 var assigned_chars: Array=[]
 for c in sim.characters:
  if c.room==selected:assigned_chars.append(c.name)
 if assigned_chars.size()>0:
  txt("Staff: "+", ".join(assigned_chars),x+24,460,11,MUTED)

 draw_line(Vector2(x+24,485),Vector2(x+414,485),Color("1e2c33"),1)
 icon("gear",Vector2(x+38,515),Color("94a3b8"),1.0)
 txt("PRODUCTION RATE",x+56,508,10,MUTED)
 if info.output!="":
  var rate_h=sim.gross_output(selected)*60.0
  txt("%.1f /h" % rate_h,x+56,532,18,INK)
  txt("(+%.2f/s %s)" % [sim.gross_output(selected),info.output],x+148,532,12,Color("22d3ee"))
 elif kind=="lab":
  txt("%d Scientist(s) Active" % sim.scientist_count(),x+56,532,15,Color("22d3ee"))
 elif kind=="security":
  txt("+%d Defense Boost" % (18*r.workers*r.level),x+56,532,15,Color("22d3ee"))
 else:
  txt("+%d Capacity" % (4*int(r.level)),x+56,532,15,Color("22d3ee"))

 draw_line(Vector2(x+24,555),Vector2(x+414,555),Color("1e2c33"),1)
 button(Rect2(1360,568,68,50),"−",func():action(sim.assign(selected,-1)),false,r.workers==0,"Return a survivor to available pool",22)
 button(Rect2(1440,568,68,50),"+",func():action(sim.assign(selected,1)),false,r.workers>=3 or sim.idle_workers()==0,"Assign an available survivor",22)
 txt("ASSIGN SURVIVOR",x+24,584,12,MUTED)
 txt("%d idle available" % sim.idle_workers(),x+24,604,11,Color("22d3ee"))

 var up_cost=sim.upgrade_cost(selected)
 var can_up=r.level<3 and sim.stock.scrap>=up_cost and r.build_left<=0
 var up_lbl="UPGRADE TO LEVEL %d\n⚙ %d SCRAP" % [r.level+1,up_cost] if r.level<3 else "MAXIMUM LEVEL REACHED"
 button(Rect2(x+24,634,390,50),up_lbl,func():action(sim.upgrade_room(selected)),can_up,not can_up,"Upgrades increase room output and capacity",13)

 var room_em=""
 for em in sim.emergencies:
  if em.room==selected:room_em=em.kind;break
 if room_em!="":
  box(Rect2(x+24,694,390,38),Color("4a120e"),RED,6)
  txt("⚠ EMERGENCY: "+room_em.to_upper(),x+36,718,11,INK)
  button(Rect2(x+276,698,130,30),"Suppress",func():action(sim.suppress_emergency(selected));play_sound("click");spawn_floating_text("Suppressed!",mouse,TEAL),true,false,"Extinguish emergency",11)

 draw_line(Vector2(x+24,742),Vector2(x+414,742),Color("1e2c33"),1)
 txt("ENTRANCE DEFENSE",x+24,764,10,MUTED)
 txt(str(sim.defense()),x+358,767,18,Color("22d3ee"))
 txt("Next raid in %ds" % ceili(sim.raid_in),x+24,784,11,RED if sim.raid_in<20 else MUTED)
 button(Rect2(x+24,796,190,40),"Fortify · 30 ⏻",func():action(sim.brace()),false,sim.braced or sim.stock.energy<30,"+45 defense for next raid",12)
 button(Rect2(x+224,796,190,40),"Repair · 35 🔩",func():action(sim.repair()),false,sim.integrity>=100 or sim.stock.scrap<35,"Restore 25 integrity",12)
 button(Rect2(x+24,846,190,34),"⚡ Overclock",func():action(sim.use_ability("overclock",selected)),false,sim.stock.energy<25 or float(sim.abilities.get("overclock",{}).get("timer",0.0))>0,"200% production boost for 20s",11)
 button(Rect2(x+224,846,190,34),"🍽 Rationing",func():action(sim.use_ability("rationing")),false,float(sim.abilities.get("rationing",{}).get("timer",0.0))>0,"Halve food & water use for 30s",11)

func draw_build(x: float) -> void:
 txt("CONSTRUCTION CATALOG",x+24,308,18,GOLD)
 txt("Expand Shelter 07",x+24,328,10,MUTED)
 draw_line(Vector2(x+24,342),Vector2(x+414,342),Color("1e2c33"),1)
 var empty=sim.rooms[selected].kind==""
 txt("Chamber %02d selected" % (selected+1) if empty else "Select an empty chamber in the cutaway.",x+24,362,12,Color("22d3ee") if empty else MUTED)
 var kinds=["lab","workshop","security","dorm","power","water","food","medbay"]
 for i in range(kinds.size()):
  var kind: String=kinds[i];var info: Dictionary=Sim.ROOM_TYPES[kind]
  var px=1174.0+(i%2)*194.0;var py=475.0+int(i/2)*102.0
  box(Rect2(px,py,186,94),Color("121f26"),Color("253842"),6)
  draw_texture_rect(textures[kind],Rect2(px+2,py+2,182,48),false)
  txt(info.name,px+8,py+66,11,INK)
  var can_build=empty and sim.stock.scrap>=info.cost
  txt("%d scrap" % info.cost,px+8,py+83,10,GOLD if sim.stock.scrap>=info.cost else RED)
  button(Rect2(px+126,py+50,56,36),"+",func():build(kind),can_build,not can_build,info.desc,18)
 txt("14s to build · staff new rooms after construction",x+24,896,11,MUTED)

func draw_people(x: float) -> void:
 txt("THE SURVIVORS",x+24,308,18,Color("22d3ee"))
 txt("%d available · %d on expedition" % [sim.idle_workers(),2 if not sim.expedition.is_empty() else 0],x+24,328,11,MUTED)
 draw_line(Vector2(x+24,342),Vector2(x+414,342),Color("1e2c33"),1)
 for i in range(mini(sim.characters.size(),6)):
  var c: Dictionary=sim.characters[i]
  var y=356+i*78
  box(Rect2(x+20,y,398,70),Color("121f26"),Color("253842"),6)
  box(Rect2(x+26,y+8,48,52),Color("1e2f37"),Color("22d3ee"),6)
  centered(c.name.left(1),Rect2(x+26,y+8,48,52),18,Color("22d3ee"))
  txt("%s · Lv.%d" % [c.name,c.level],x+84,y+22,14,INK)
  txt(c.get("trait","Survivor"),x+240,y+22,10,GOLD)
  var r_name="Idle"
  if c.get("on_expedition",false):r_name="Expedition"
  elif c.room>=0 and c.room<sim.rooms.size() and sim.rooms[c.room].kind!="":r_name=Sim.ROOM_TYPES[sim.rooms[c.room].kind].name
  txt("%s · S%d I%d A%d C%d E%d" % [r_name,c.str,c.int,c.agi,c.cha,c.end],x+84,y+38,10,MUTED)
  meter(x+84,y+50,110,c.hp/c.max_hp,Color("76bf86") if c.hp>40 else RED,4)
  meter(x+204,y+50,110,c.energy/100.0,Color("22d3ee"),4)
  if c.level>=2 and c.perks.size()<c.level-1:
   button(Rect2(x+326,y+16,82,36),"★ Perk",func():perk_modal_char_id=c.id;modal="perk",true,false,"Choose a specialization perk",11)
  else:
   var perk_txt="★ %d" % c.perks.size() if c.perks.size()>0 else "Ready"
   txt(perk_txt,x+346,y+36,11,GOLD if c.perks.size()>0 else MUTED)
 txt("Drag survivors into rooms to assign roles.",x+24,840,11,TEAL)
 txt("STR->Workshop, INT->Lab/Water, AGI->Food",x+24,860,10,MUTED)
 txt("Survivors level up and unlock specialized perks.",x+24,880,10,MUTED)

func draw_research(x: float) -> void:
 txt("RESEARCH & ARCHIVES",x+24,308,18,Color("22d3ee"))
 txt("%d scientist(s) assigned" % sim.scientist_count(),x+24,328,11,MUTED)
 draw_line(Vector2(x+24,342),Vector2(x+414,342),Color("1e2c33"),1)
 var i=0
 for key in ["efficiency","defense","relay"]:
  var info: Dictionary=Sim.RESEARCH[key];var y=483.0+i*126.0
  box(Rect2(1174,y-5,376,118),Color("121f26"),Color("253842"),6)
  txt(info.name,1188,y+20,16,Color("22d3ee") if key in sim.unlocked else INK)
  paragraph(info.desc,1188,y+42,345,11,MUTED,16)
  var active=sim.research.get("key","")==key
  if active:
   meter(1188,y+80,348,1-sim.research.left/sim.research.total,Color("22d3ee"),4)
   txt("%ds left" % ceili(sim.research.left/maxi(1,sim.scientist_count())) if sim.scientist_count()>0 and sim.stock.energy>0 else "Paused · needs a scientist and power",1188,y+98,11,Color("22d3ee"))
  else:
   var title="Completed" if key in sim.unlocked else "Research · %d scrap" % info.cost
   button(Rect2(1184,y+70,356,36),title,func():action(sim.start_research(key)),false,key in sim.unlocked or not sim.research.is_empty() or sim.scientist_count()==0 or sim.stock.scrap<info.cost or (key=="relay" and "efficiency" not in sim.unlocked),"Requires a staffed lab and power",12)
  i+=1
 txt("Research pauses while the lab is unstaffed or unpowered.",x+24,888,11,MUTED)

func draw_map(x: float) -> void:
 txt("WASTELAND EXPEDITIONS",x+24,308,18,Color("22d3ee"))
 txt("2 survivors + 12 food per expedition",x+24,328,11,MUTED)
 draw_line(Vector2(x+24,342),Vector2(x+414,342),Color("1e2c33"),1)
 var area=Rect2(x+20,360,398,140);box(area,Color("111d22"),Color("253842"),6)
 for n in range(11):draw_line(Vector2(x+28+n*36,364),Vector2(x+28+n*36,494),Color("1d2c33"),1)
 for n in range(4):draw_line(Vector2(x+24,376+n*34),Vector2(x+414,376+n*34),Color("1d2c33"),1)
 var points=[Vector2(x+60,440),Vector2(x+160,390),Vector2(x+280,450),Vector2(x+350,400)]
 draw_polyline(PackedVector2Array(points),Color("557a68"),2,true)
 for p in points:draw_circle(p,5,GOLD,true,-1,true);draw_arc(p,12,0,TAU,24,Color("71836a"),1,true)
 txt("SHELTER 07",x+35,470,9,Color("22d3ee"));txt("DEPOT",x+140,380,9,MUTED);txt("RESERVOIR",x+245,470,9,MUTED);txt("OUTPOST",x+325,385,9,MUTED)
 if not sim.expedition.is_empty():
  var ex: Dictionary=sim.expedition
  txt("Team en route: "+ex.route.capitalize(),x+24,530,16,Color("22d3ee"))
  meter(x+24,550,390,1-ex.left/ex.total,Color("22d3ee"),5)
  txt("Returning in %ds" % ceili(ex.left),x+24,580,13,MUTED)
  paragraph("The team is safe. Keep the shelter running until they return with supplies.",x+24,610,380,14)
 else:
  var i=0
  for route in ["depot","reservoir","outpost"]:
   var y=525+i*85
   txt({"depot":"Abandoned depot","reservoir":"Old reservoir","outpost":"Survivor outpost"}[route],x+24,y+14,15)
   txt({"depot":"85–115 scrap + 24 food · 32s","reservoir":"100 water + 42 food · 32s","outpost":"Recruit survivor + supplies · 46s"}[route],x+24,y+35,11,MUTED)
   button(Rect2(x+300,y,105,42),"Dispatch",func():action(sim.start_expedition(route)),false,sim.idle_workers()<2 or sim.stock.food<12,"A team reserves two available survivors",12)
   i+=1

func draw_footer() -> void:
 var nav_items=[
  {"id":"Shelter","label":"SHELTER","icon":"shelter","tab":"Shelter"},
  {"id":"Expedition","label":"EXPEDITION","icon":"backpack","tab":"Map"},
  {"id":"Research","label":"RESEARCH","icon":"book","tab":"Research"},
  {"id":"Survivors","label":"SURVIVORS","icon":"survivors","tab":"People"},
  {"id":"Log","label":"LOG","icon":"log","modal":"journal"}
 ]
 var start_x=12.0;var btn_w=307.0;var gap=10.0;var btn_y=938.0;var btn_h=48.0
 for i in range(nav_items.size()):
  var item=nav_items[i]
  var r=Rect2(start_x+i*(btn_w+gap),btn_y,btn_w,btn_h)
  var is_active=(item.get("tab","")!="" and tab==item.tab) or (item.get("modal","")!="" and modal==item.modal)
  var is_hover=r.has_point(mouse)
  var bg_col=Color("1a3d3d") if is_active else (Color("18242a") if is_hover else Color("111a1e"))
  var border_col=Color("22d3ee") if is_active else (Color("3b525c") if is_hover else Color("223138"))
  var content_col=Color("22d3ee") if is_active else (Color("f1f5f9") if is_hover else Color("889fa8"))
  box(r,bg_col,border_col,6,2 if is_active else 1)
  icon(item.icon,Vector2(r.position.x+r.size.x*0.35,r.position.y+24),content_col,0.85)
  txt(item.label,r.position.x+r.size.x*0.42,r.position.y+29,14,content_col)
  hitboxes.append({"rect":r,"action":func():
   if item.get("tab","")!="":set_tab(item.tab)
   elif item.get("modal","")!="":modal=item.modal
  })

func draw_modal() -> void:
 hitboxes.clear()
 draw_rect(Rect2(0,0,1600,1000),Color(.018,.035,.044,.86))
 var r=Rect2(446,186,708,626);box(r,PANEL,Color("566762"),14,2)
 button(Rect2(1093,205,39,37),"×",func():if modal=="encounter":sim.resolve_encounter(1);modal="",false,false,"Close · Escape",24)
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
 elif modal=="encounter":
  var enc: Dictionary=sim.active_encounter
  txt("WASTELAND ENCOUNTER",484,239,11,GOLD);txt(enc.get("title","Wasteland Event"),484,286,30)
  paragraph(enc.get("desc","Your scavenging team encountered an unexpected situation in the wasteland."),484,330,620,17,INK,26)
  button(Rect2(484,480,632,54),enc.get("opt1","Option 1"),func():
   sim.resolve_encounter(1);modal="";play_sound("coin");spawn_floating_text("Encounter Resolved!",mouse,TEAL)
  ,true,false,"",15)
  button(Rect2(484,555,632,54),enc.get("opt2","Option 2"),func():
   sim.resolve_encounter(2);modal="";play_sound("coin");spawn_floating_text("Encounter Resolved!",mouse,GOLD)
  ,false,false,"",15)
 elif modal=="perk":
  var target_char=null
  for c in sim.characters:
   if c.id==perk_modal_char_id:target_char=c;break
  var char_name=target_char.name if target_char!=null else "Survivor"
  txt("SPECIALIZATION TRAINING",484,236,11,TEAL)
  txt(char_name+" · Choose a Perk",484,278,28)
  paragraph("Select a permanent specialization to adapt this survivor to bunker roles.",484,310,620,14,MUTED,20)
  var perk_keys=["fast_learner","engineer","green_thumb","medic","scavenger","tough"]
  for i in range(perk_keys.size()):
   var p_key=perk_keys[i]
   var p_info: Dictionary=Sim.PERKS[p_key]
   var px=484+(i%2)*322;var py=345+int(i/2)*125
   var has_p=target_char!=null and p_key in target_char.perks
   box(Rect2(px,py,310,114),Color("15262c"),LINE,8)
   txt(p_info.name,px+14,py+24,15,GOLD if not has_p else MUTED)
   paragraph(p_info.desc,px+14,py+46,280,11,MUTED,16)
   button(Rect2(px+14,py+80,280,26),"Learned" if has_p else "Acquire Perk",func():
    if not has_p:
     sim.choose_perk(perk_modal_char_id,p_key)
     modal="";play_sound("levelup");spawn_floating_text("Perk Learned!",mouse,GOLD)
   ,not has_p,has_p,"",12)

func select_room(index: int) -> void:
 selected=index
 if sim.rooms[index].kind=="":tab="Build"
 else:tab="Shelter"

func set_tab(value: String) -> void:
 if value=="Expedition":tab="Map"
 elif value=="Survivors":tab="People"
 elif value=="Log":modal="journal"
 else:tab=value
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
 for view in ["help","journal","menu","restart","victory","defeat","encounter","perk"]:
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

"""Rebuild all original New Dawn artwork with Blender, no external assets required.
blender --background --python art/build_assets.py
Pass -- --quick for lower sample previews or --only power to rerender one scene.
"""
import bpy, math, random, os, sys
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'renders')
os.makedirs(OUT, exist_ok=True)
random.seed(19)
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
ONLY = ARGS[ARGS.index('--only')+1] if '--only' in ARGS else None
QUICK = '--quick' in ARGS

def material(name, color, metallic=0, rough=.5, emission=0):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color,1); m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color,1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color,1)
        p.inputs['Emission Strength'].default_value = emission
    return m

M = {}
for name, col, metal, rough, glow in [
 ('steel',(.12,.19,.22),.75,.36,0),('trim',(.055,.083,.10),.65,.36,0),
 ('wall',(.27,.31,.29),.25,.75,0),('floor',(.12,.16,.17),.6,.5,0),
 ('cream',(.66,.63,.48),.18,.65,0),('orange',(.83,.32,.065),.45,.32,0),
 ('yellow',(.98,.64,.12),.4,.35,0),('blue',(.045,.30,.43),.55,.3,0),
 ('white',(.74,.83,.80),.25,.35,0),('glass',(.014,.09,.13),.65,.2,0),
 ('cyan',(.06,.63,1.0),.25,.25,4),('warm',(1,.64,.20),.2,.3,5),
 ('light',(.57,.88,1),.1,.25,6),('green',(.35,.75,.14),.05,.6,0),
 ('leaf',(.09,.29,.09),0,.8,0),('red',(.69,.10,.045),.25,.6,0),
 ('skin',(.62,.34,.17),0,.7,0),('hair',(.055,.031,.022),0,.85,0),
 ('cloth',(.09,.23,.28),0,.9,0),('wood',(.30,.18,.10),0,.8,0),
 ('sand',(.44,.24,.13),0,.95,0),('rock',(.24,.135,.087),0,.98,0),
 ('distant',(.40,.27,.26),0,1,0),('sky',(.32,.48,.60),0,1,0)]:
    M[name] = material(name,col,metal,rough,glow)

def assign(o, mat):
    o.data.materials.append(M[mat] if isinstance(mat,str) else mat)
    return o

def cube(name, loc, dims, mat, bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name
    o.dimensions=dims; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(o,mat)
    if bevel:
        mod=o.modifiers.new('Soft machined edges','BEVEL'); mod.width=bevel; mod.segments=2
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def sphere(name,loc,scale,mat,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale; assign(o,mat)
    for p in o.data.polygons:p.use_smooth=True
    return o

def cyl(name,loc,radius,depth,mat,rot=None,vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
    o=bpy.context.object; o.name=name
    if rot:o.rotation_euler=rot
    assign(o,mat); mod=o.modifiers.new('Edge highlights','BEVEL');mod.width=.035;mod.segments=2
    o.modifiers.new('Normals','WEIGHTED_NORMAL')
    return o

def bar(name,a,b,r,mat):
    a,b=Vector(a),Vector(b);o=cyl(name,(a+b)/2,r,(b-a).length,mat)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def text3(body,loc,size,mat='cream',align='CENTER'):
    c=bpy.data.curves.new('Lettering','FONT');c.body=body;c.size=size;c.align_x=align;c.extrude=.001
    o=bpy.data.objects.new(body,c);bpy.context.collection.objects.link(o);o.location=loc;o.rotation_euler=(math.pi/2,0,0);assign(o,mat);return o

def light(name,loc,color,power,size=3,target=(0,0,1)):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def camera(loc,target,scale):
    d=bpy.data.cameras.new('Camera');o=bpy.data.objects.new('Camera',d);bpy.context.collection.objects.link(o)
    o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=scale;bpy.context.scene.camera=o

def scene(name,w,h,transparent=True):
    s=bpy.data.scenes.new(name);bpy.context.window.scene=s
    s.render.engine='CYCLES';s.cycles.samples=12 if QUICK else 32;s.cycles.use_denoising=True
    s.render.resolution_x=w;s.render.resolution_y=h;s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=transparent
    s.world=bpy.data.worlds.new(name+' world');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.20,.29,.39,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.35
    s.view_settings.view_transform='AgX'
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
        for d in prefs.devices:d.use=d.type=='OPTIX'
        if any(d.type=='OPTIX' for d in prefs.devices):s.cycles.device='GPU'
    except Exception:pass
    return s

def render(name):
    s=bpy.context.scene;s.render.filepath=os.path.join(OUT,name+'.png');bpy.ops.render.render(write_still=True)
    print('ASSET_COMPLETE '+name,flush=True)

def monitor(x,y,z,w=1.1,h=.70):
    cube('Monitor housing',(x,y,z),(w,.14,h),'trim')
    cube('Blue phosphor screen',(x,y-.081,z),(w-.10,.02,h-.10),'glass',.015)
    for i in range(4):
        cube('Screen readout',(x-w*.32,y-.099,z+h*.25-i*h*.15),(random.uniform(.15,w*.52),.009,.014),'cyan',0)
    cube('Screen status',(x+w*.3,y-.10,z-.18),(w*.08,.013,.04),'warm',0)
    bar('Monitor stand',(x,y,z-h/2),(x,y,z-h/2-.22),.035,'steel')

def person(x,y,z=0,style='cloth',pose=0):
    # Original stylized miniatures, proportioned for the shelter diorama.
    for dx in [-.105,.105]:
        cube('Boot',(x+dx,y-.06,z+.13),(.18,.31,.19),'trim')
        bar('Trouser leg',(x+dx,y,z+.22),(x+dx,y,z+.66),.085,'cream')
    sphere('Jacket',(x,y,z+.98),(.25,.15,.38),style)
    cube('Utility belt',(x,y,z+.76),(.45,.32,.07),'wood')
    cyl('Neck',(x,y,z+1.33),.07,.14,'skin')
    sphere('Face',(x,y-.015,z+1.51),(.19,.17,.23),'skin',3)
    sphere('Hair',(x,y+.035,z+1.62),(.195,.17,.16),'hair')
    for dx in [-.065,.065]:sphere('Eyes',(x+dx,y-.177,z+1.53),(.02,.02,.022),'trim',1)
    if style=='orange':
        sphere('Hard hat',(x,y,z+1.71),(.23,.20,.13),'yellow');cube('Hat brim',(x,y-.035,z+1.67),(.49,.43,.045),'yellow')
    for side in [-1,1]:
        a=(x+side*.20,y,z+1.16);b=(x+side*.31,y-.10,z+.91);c=(x+side*.22,y-.31,z+.97)
        bar('Sleeve',a,b,.085,style);bar('Forearm',b,c,.06,style);sphere('Hand',c,(.07,.065,.07),'skin')
    cube('Tablet',(x,y-.36,z+1.0),(.38,.055,.25),'trim',.015)
    cube('Tablet display',(x,y-.397,z+1.0),(.29,.009,.16),'cyan',.008)

def plant(x,y,z,scale=1):
    cyl('Planter',(x,y,z+.19*scale),.23*scale,.38*scale,'cream')
    for a in range(7):
        ang=a*2.4;end=(x+math.cos(ang)*.31*scale,y+math.sin(ang)*.20*scale,z+random.uniform(.6,1.05)*scale)
        bar('Stem',(x,y,z+.30*scale),end,.018*scale,'leaf')
        o=sphere('Leaves',end,(.10*scale,.065*scale,.30*scale),'green');o.rotation_euler=(.4*math.sin(ang),.8*math.cos(ang),ang)

def room_shell(accent='warm'):
    cube('Foundation',(0,0,-.10),(10.6,3.8,.32),'trim',.1)
    cube('Backwall',(0,1.64,2.03),(10.4,.2,4.1),'wall',.05)
    for x in [-5.12,5.12]:cube('Sidewall',(x,0,2.06),(.23,3.55,4.2),'steel')
    for i in range(10):
        x=-4.5+i
        cube('Wall panel',(x,1.50,2.04),(.97,.08,3.90),'wall',.015)
        for z in [.36,3.69]:cyl('Panel bolt',(x+.37,1.44,z),.033,.025,'steel',(math.pi/2,0,0),12)
        for j in range(4):cube('Floor tile',(x,-1.30+j*.77,.085),(.96,.74,.035),'floor',.01)
    for z in [3.68,3.91]:
        bar('Service pipe',(-4.9,1.19,z),(4.9,1.19,z),.065,'steel')
        for x in [-4,-2,0,2,4]:cube('Pipe bracket',(x,1.2,z),(.06,.24,.22),'trim',.01)
    for x in [-4.78,4.78]:
        bar('Vertical pipe',(x,1.1,.20),(x,1.1,3.72),.09,'steel')
        cube('Vent',(x,1.15,2.6),(.32,.3,.70),'trim')
        for z in [2.35,2.48,2.61,2.74]:cube('Vent slat',(x,.976,z),(.25,.03,.028),'cream',0)
    for x in [-3,2.6]:
        cube('Light housing',(x,.05,3.92),(2.9,.50,.14),'trim')
        cube('Ceiling lamp',(x,-.03,3.83),(2.52,.32,.03),accent)
        light('Practical',(x,-.02,3.62),(1,.65,.30) if accent=='warm' else (.35,.73,1),220,2,(x,.5,0))
    for x in [-5.05,5.05]:
        cube('Front jamb',(x,-1.81,2.0),(.22,.27,4.20),'trim')
        cube('Edge inlay',(x,-1.97,2.0),(.035,.018,3.74),'steel')
    cube('Lintel',(0,-1.81,4.07),(10.3,.27,.19),'trim')
    cube('Sill',(0,-1.81,.09),(10.3,.27,.17),'steel')
    light('Softbox',(0,-8,5),(.55,.72,1),440,8,(0,0,1.4))
    camera((0,-21,7.1),(0,0,1.98),11.15)

def contents(kind):
    if kind=='command':
        cube('Map frame',(-.5,1.28,2.55),(5.0,.22,2.15),'trim')
        cube('Map blue',(-.5,1.14,2.55),(4.77,.035,1.95),'glass')
        for i in range(17):cube('Map longitude',(-2.78+i*.285,1.114,2.55),(.008,.008,1.92),'blue',0)
        for i in range(8):cube('Map latitude',(-.5,1.11,1.67+i*.25),(4.72,.008,.009),'blue',0)
        rng=random.Random(8)
        for i in range(72):
            x=rng.uniform(-2.7,1.7);z=rng.uniform(1.78,3.25)
            if math.sin(x*3+z*2)>.0:sphere('Map terrain',(x,1.09,z),(.14,.025,.10),'cyan',1)
        text3('NEW DAWN // RELAY 07',(-.5,1.071,3.32),.17,'light')
        cube('Operations desk',(-.2,.40,1.02),(7.4,1.05,.16),'steel')
        for x in [-3,0,3]:
            cube('Desk cabinet',(x,.53,.52),(.86,.7,.97),'trim');monitor(x,.40,1.55,.95,.58)
            cyl('Stool',(x,-.58,.58),.29,.13,'cloth');bar('Stool leg',(x,-.58,.13),(x,-.58,.56),.07,'steel')
        monitor(-4.15,1.24,2.42,.65,1.15);monitor(3.33,1.20,2.73,1.55,1.16)
        person(-1.8,-.9);person(2,-.7,style='cream');plant(4.30,.65,0,.95)
    elif kind=='power':
        cube('Generator base',(-.5,.12,.31),(5.6,2.3,.45),'trim')
        cyl('Turbine',(-.6,.10,1.52),1.05,4.6,'steel',(0,math.pi/2,0),48)
        for x in [-2.8,-2.35,-1.8,.6,1.18,1.55]:
            cyl('Turbine band',(x,.10,1.52),1.11,.14,'orange' if x in [-2.35,1.18] else 'trim',(0,math.pi/2,0),48)
        for x in [-2.25,1.09]:cyl('Amber energy ring',(x,.1,1.52),1.065,.055,'warm',(0,math.pi/2,0),48)
        cube('Generator face',(-.5,-.974,1.61),(1.14,.17,.85),'trim');text3('Z',(-.5,-1.08,1.32),.65,'warm')
        for x in [-1.5,.4]:
            for z in [1.2,1.45,1.7,1.95]:cube('Cooling grille',(x,-.88,z),(.46,.13,.045),'cream')
        bar('Exhaust',(-1.8,.7,2.1),(-1.8,.7,3.5),.16,'steel');bar('Exhaust',(-1.8,.7,3.5),(3.8,.7,3.5),.16,'steel')
        cube('Control cabinet',(3.65,.85,1.05),(1.4,1,2),'blue');monitor(3.65,.28,1.73,.91,.71)
        for z in [.4,.6,.8]:cube('Cabinet grille',(3.65,.33,z),(1.1,.03,.05),'trim')
        person(2.30,-.91,style='orange');text3('POWER / 01',(-3,1.32,3.19),.23)
    elif kind=='water':
        for x,r,h in [(-2.6,.75,2.75),(-.55,.91,3.05),(2.15,.68,2.52)]:
            cyl('Water vessel',(x,.40,h/2+.19),r,h,'blue',vertices=48)
            sphere('Tank dome',(x,.4,h+.13),(r,r,.26),'blue')
            cyl('Tank band',(x,.4,1.45),r+.025,1.04,'white',vertices=48)
            text3('H2O',(x,.4-r-.037,1.34),.30,'blue')
            for z in [.25,2.4]:cyl('Tank rim',(x,.40,z),r+.04,.08,'steel',vertices=48)
            bar('Feed pipe',(x,.5,h+.23),(x,.5,3.55),.06,'steel')
        bar('Manifold',(-3.5,.5,3.56),(3.8,.5,3.56),.09,'blue')
        monitor(3.91,.83,2.08,1,1.48);person(1.15,-1.08,style='white')
    elif kind=='food':
        for x in [-2.85,.05]:
            for z in [.78,1.68,2.58]:
                cube('Grow tray',(x,.69,z),(2.63,1.13,.15),'white')
                cube('Soil',(x,.69,z+.085),(2.44,.94,.05),'wood')
                for dx in [-.92,-.47,0,.47,.92]:
                    for y in [.41,.97]:
                        for a in range(3):
                            o=sphere('Hydroponic leaf',(x+dx+.09*math.sin(a*2),y,z+.24),(.17,.1,.24),'green');o.rotation_euler=(.4,a*.9,a)
                cube('Grow LED',(x,.8,z+.65),(2.4,.035,.036),'light')
            for dx in [-1.3,1.3]:bar('Rack',(x+dx,.68,.12),(x+dx,.68,3.40),.055,'steel')
        cube('Kitchen counter',(3.20,.48,.94),(2.05,1.4,.13),'cream')
        cube('Kitchen cabinet',(3.20,.75,.47),(1.99,.8,.88),'steel')
        for x in [2.7,3.2,3.6]:sphere('Harvest',(x,.38,1.1),(.16,.17,.15),'red')
        person(1.5,-.93,style='cream');text3('GROW / TOGETHER',(2.98,1.35,2.95),.25)
    elif kind=='dorm':
        for x in [-2.9,1.25]:
            for z in [.6,2.0]:
                cube('Bed frame',(x,.37,z),(3.20,1.75,.15),'steel')
                cube('Mattress',(x,.37,z+.15),(2.98,1.61,.22),'cream',.10)
                cube('Blanket',(x+.40,.36,z+.27),(1.80,1.58,.10),'cloth',.09)
                cube('Pillow',(x-1.07,.37,z+.32),(.60,1.08,.17),'white',.13)
            for dx in [-1.60,1.60]:
                for y in [-.5,1.26]:bar('Bed post',(x+dx,y,.16),(x+dx,y,3.05),.055,'steel')
            for z in [.65,1.07,1.49,1.91,2.33]:bar('Ladder rung',(x+1.31,-.60,z),(x+1.65,-.60,z),.035,'cream')
        cube('Locker',(3.99,.54,1.42),(1,1,2.8),'blue')
        for z in [1.68,1.82,1.96]:cube('Locker vent',(3.99,.015,z),(.65,.035,.04),'trim')
        person(.0,-1.13);cube('Rug',(.1,-.62,.13),(1.6,1.25,.02),'wood',0)
    elif kind=='lab':
        for x in [-3.5,0,3.5]:
            cube('Lab bench',(x,.55,.60),(2.7,1.55,1.1),'white')
            cube('Black worktop',(x,.50,1.22),(2.82,1.65,.11),'trim')
            monitor(x,.6,1.92,1.21,.83)
        for x in [-3.9,-3.3,-.3,.2]:
            cyl('Sample',(x,-.02,1.56),.11,.53,'cyan');cyl('Sample lid',(x,-.02,1.84),.13,.05,'steel')
        cube('Research display',(0,1.30,2.91),(2.9,.20,1.11),'glass')
        text3('RECONNECT',(0,1.16,2.86),.36,'light');person(2,-1.1,style='white');plant(-4.6,.9,0,.75)
    elif kind=='medbay':
        cube('Medical cross V',(0,1.35,2.88),(.28,.09,1.2),'red');cube('Medical cross H',(0,1.31,2.88),(1.16,.09,.29),'red')
        for x in [-2.6,1.6]:
            cube('Patient bed',(x,-.02,.91),(3.15,1.64,.25),'steel');cube('Bed linen',(x,-.02,1.10),(3.02,1.52,.22),'white',.1)
            cube('Pillow',(x-1.1,-.01,1.30),(.64,1.10,.19),'cream',.1)
            for dx in [-1.3,1.3]:bar('Bed support',(x+dx,0,.11),(x+dx,0,.84),.08,'steel')
            monitor(x,1.1,2.1,.8,.7)
        person(.05,-1.2,style='white')
    elif kind=='workshop':
        cube('Tool board',(0,1.26,2.40),(6.2,.2,1.68),'blue')
        for x in [-2.7,-2,-1.3,-.6,.1,.8,1.5,2.2,2.9]:
            bar('Hanging tool',(x,1.05,2.1),(x,1.05,2.9),.055,'yellow');cube('Tool head',(x,1.05,2.9),(.30,.16,.11),'steel')
        cube('Workbench',(0,.45,1.06),(7.8,1.4,.21),'wood')
        for x in [-3.1,3.1]:cube('Drawers',(x,.55,.51),(1.5,1.2,.95),'steel')
        cyl('Machine part',(-.8,.3,1.41),.40,.55,'steel',(0,math.pi/2,0));monitor(2,.6,1.67);person(.4,-1.05,style='orange')
    elif kind=='security':
        cube('Armory',(2.4,.8,1.52),(3.4,1,2.8),'steel')
        for x in [1.2,2,2.8,3.6]:
            cube('Equipment locker',(x,.23,1.52),(.72,.14,2.58),'blue')
            cube('Shield',(x,.07,1.7),(.46,.14,.63),'cream');text3('+',(x,-.02,1.57),.35,'blue')
        cube('Defense console',(-2.7,.45,1.0),(3.2,1.4,1.8),'trim');monitor(-2.7,-.3,1.76,2.7,1.13)
        person(-.2,-1.05,style='orange');text3('PROTECT / PRESERVE',(-1.2,1.34,3.0),.26)
    elif kind=='empty':
        for x in [-3.8,3.8]:
            cube('Construction upright',(x,.8,1.85),(.16,.16,3.6),'yellow')
            for z in [.7,1.4,2.1,2.8]:bar('Scaffold rung',(x-.48,.8,z),(x+.48,.8,z),.035,'steel')
        for x in [-2.3,-1.1]:cube('Crate',(x,.85,.52),(.85,.8,.9),'wood')
        text3('RESERVED',(.9,1.33,2.26),.5,'cream');text3('A BRIGHTER TOMORROW',(.9,1.33,1.88),.17,'cream')

def surface():
    s=scene('Surface',1600,520,False)
    s.world.node_tree.nodes['Background'].inputs[0].default_value=(.32,.47,.64,1)
    s.world.node_tree.nodes['Background'].inputs[1].default_value=.55
    # Layered canyon silhouettes, warm desert road and fortified entry.
    cube('Desert',(0,4,-.37),(42,29,.65),'sand',.1)
    rng=random.Random(12)
    for y,count in [(23,17),(16,12)]:
        for i in range(count):
            x=-24+i*3.6;h=rng.uniform(1.5,4.6)
            o=sphere('Sandstone mesa',(x,y,h*.3),(rng.uniform(1.5,3),2,h*.60),'distant' if y==15 else 'sand',1)
            o.rotation_euler[2]=rng.random()
    for i in range(60):
        x=rng.uniform(-17,17);y=rng.uniform(-1.2,7)
        if abs(x)<5 and y<2:continue
        sphere('Desert stone',(x,y,.08),(rng.uniform(.10,.5),rng.uniform(.1,.5),rng.uniform(.1,.4)),'rock',1)
    # Hillside; bunker door remains fully visible.
    for x in [6,9,12,15]:sphere('Bunker hill',(x,5.5,1.1),(3.0,2.4,2.5),'rock',1)
    cube('Fortification',(3,1.58,1.69),(11.6,2.0,3.45),'wall',.18)
    cube('Dark entry',(1,-.01,1.43),(3.25,.30,2.9),'trim',.1)
    for x in [-.78,2.78]:cube('Door pier',(x,-.28,1.47),(.42,.7,3.26),'cream',.1)
    cube('Door lintel',(1,-.28,3.12),(4,.71,.41),'cream',.1)
    cube('Door interior',(1,-.20,1.50),(2.60,.05,2.70),'steel')
    for x in [.33,1.67]:cube('Blast door',(x,-.30,1.47),(1.28,.12,2.67),'trim')
    cube('Door amber lamp',(1,-.66,2.90),(2.1,.06,.09),'warm')
    for z in [.22,.44]:cube('Entry stairs',(1,-.82-z*2,z/2),(4.2,.8+z*2,z),'steel')
    text3('07',(4.3,.53,1.42),1.0,'cream');text3('NEW DAWN',(6.5,.53,2.7),.35,'cream')
    text3('REBUILD\nTOGETHER',(6.55,.53,1.74),.25,'cream')
    # Sapphire hanging banner, with original shelter emblem.
    cube('Banner',(7.90,.49,1.80),(.91,.08,2.4),'blue')
    text3('+',(7.9,.435,1.83),.70,'cream');text3('DAWN',(7.9,.425,1.23),.15,'cream')
    # Satellite dish made as a concave radial mesh.
    bar('Dish pedestal',(2.5,2.1,3.2),(2.5,2.1,4.4),.23,'steel')
    verts=[];faces=[];rings=9;segments=40
    for j in range(rings):
        r=j/(rings-1)*1.8
        for i in range(segments):
            a=i*math.tau/segments;verts.append((r*math.cos(a),r*math.sin(a),r*r*.24))
    for j in range(rings-1):
        for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
    mesh=bpy.data.meshes.new('Dish');mesh.from_pydata(verts,[],faces);mesh.update()
    dish=bpy.data.objects.new('Satellite reflector',mesh);bpy.context.collection.objects.link(dish);dish.location=(2.5,2.1,4.3);dish.rotation_euler=(math.radians(32),math.radians(-18),0);assign(dish,'cream')
    sol=dish.modifiers.new('Dish thickness','SOLIDIFY');sol.thickness=.045
    bpy.context.view_layer.update()
    for a in range(8):
        ang=a*math.tau/8;pts=[]
        for j in range(9):
            r=j/8*1.79;p=dish.matrix_world @ Vector((r*math.cos(ang),r*math.sin(ang),r*r*.24+.035));pts.append(p)
        for j in range(8):bar('Dish rib',pts[j],pts[j+1],.018,'steel')
    bpy.context.view_layer.update()
    hub=dish.matrix_world @ Vector((0,0,2.05))
    for a in [0,2.1,4.2]:bar('Antenna strut',dish.matrix_world @ Vector((1.5*math.cos(a),1.5*math.sin(a),.54)),hub,.028,'steel')
    sphere('Receiver',hub,(.16,.16,.23),'trim')
    # Guard tower.
    for x in [-10.3,-8.8]:
        for y in [1.4,2.8]:bar('Tower support',(x,y,0),(x,y,5.1),.09,'wood')
    for z in [.8,2.1,3.4]:
        bar('Tower brace',(-10.3,1.4,z),(-8.8,1.4,z+1.3),.06,'wood');bar('Tower brace',(-8.8,1.4,z),(-10.3,1.4,z+1.3),.06,'wood')
    cube('Tower platform',(-9.55,2.1,4.13),(2.3,2.3,.18),'wood');cube('Tower roof',(-9.55,2.1,5.61),(2.7,2.6,.20),'steel')
    cube('Tower railing',(-9.55,1.02,4.52),(2.3,.11,.62),'wood')
    # Supply truck.
    cube('Truck chassis',(-5.6,-.10,.57),(4.4,1.65,.38),'trim')
    cube('Supply cargo',(-6.4,-.02,1.48),(2.55,1.72,1.58),'cloth',.12)
    for x in [-7.35,-6.65,-5.95,-5.25]:cube('Cargo rib',(x,-.91,1.48),(.05,.04,1.53),'steel')
    cube('Cab',(-4.44,-.02,1.27),(1.20,1.66,1.32),'sand',.14)
    cube('Windshield',(-4.39,-.871,1.58),(.80,.027,.57),'glass')
    cube('Truck bonnet',(-3.78,-.05,.91),(.71,1.62,.51),'sand')
    for x in [-7,-4.25]:
        for y in [-.9,.9]:
            cyl('Truck wheel',(x,y,.54),.52,.25,'trim',(math.pi/2,0,0));cyl('Wheel hub',(x,y*1.16,.54),.25,.07,'steel',(math.pi/2,0,0))
    for x in [4.3,5.25,6.2]:
        for z in [.42,1.15] if x!=6.2 else [.42]:
            cube('Supply crate',(x,-.38,z),(.84,.75,.66),'wood');cube('Crate strap',(x,-.77,z),(.10,.04,.66),'cream')
    person(-2.7,-.64,style='orange');person(3.4,-.87,style='cloth')
    for x in [-12,-8,9,11,13]:plant(x,1,0,1)
    for i in range(46):
        x=-17+i*.75;sphere('Cutaway ground lip',(x,-2.0,-.24),(rng.uniform(.5,.9),.7,rng.uniform(.25,.5)),'rock',1)
    light('Golden hour',(-10,-7,13),(1,.64,.33),2600,8,(0,1,0))
    light('Sky fill',(3,0,14),(.38,.62,1),1600,12,(0,0,1))
    light('Entry',(1,-1.2,2.7),(1,.61,.22),130,2,(1,-1,.2))
    camera((0,-32,9.5),(0,1.2,3.2),29)
    return s

if not ONLY:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for kind in ['command','power','water','food','dorm','lab','medbay','workshop','security','empty']:
    if ONLY and kind!=ONLY:continue
    scene(kind,880,380);room_shell('light' if kind in ['command','water','lab','medbay'] else 'warm');contents(kind);render(kind)
if not ONLY or ONLY=='surface':surface();render('surface')
if not ONLY:
    # Store the editable module scenes, lighting, materials and cameras together.
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art','New_Dawn.blend'))
print('BUILD_COMPLETE',flush=True)

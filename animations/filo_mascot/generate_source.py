"""Recreate Filo's original CustomPainter artwork as editable RML vector layers.

Run this only when intentionally regenerating scene.rml; hand edits live there.
No external assets, scripts inside Rive, or third-party character artwork.
"""
from pathlib import Path
from math import atan2, hypot
import xml.etree.ElementTree as E

next_id = 1
def node(parent, tag, **attrs):
    global next_id
    attrs.setdefault('id', f'0:{next_id}')
    next_id += 1
    return E.SubElement(parent, tag, {k: str(v) for k, v in attrs.items()})

root = E.Element('Rive', version='1', kind='fragment')
art = node(root, 'Artboard', name='FiloMascot', width=380, height=350)
vm = node(root, 'ViewModel', name='MascotData')
expression = node(vm, 'ViewModelPropertyNumber', name='expression')
motion = node(vm, 'ViewModelPropertyBoolean', name='motionEnabled')
left_eye = node(vm, 'ViewModelPropertyNumber', name='leftEyeOpen')
right_eye = node(vm, 'ViewModelPropertyNumber', name='rightEyeOpen')
instance = node(vm, 'ViewModelInstance', name='Default', exports='true')
vm.set('defaultInstanceId', instance.get('id'))
node(instance, 'ViewModelInstanceNumber', viewModelPropertyId=expression.get('id'), propertyValue=0)
node(instance, 'ViewModelInstanceBoolean', viewModelPropertyId=motion.get('id'), propertyValue='true')
for eye in (left_eye,right_eye):
    node(instance,'ViewModelInstanceNumber',viewModelPropertyId=eye.get('id'),propertyValue=1)
art.set('viewModelId', vm.get('id'))
art.set('viewModelInstanceId', instance.get('id'))

def shape(parent, name, geometry, color, x=0, y=0, stroke=0, **attrs):
    s = node(parent, 'Shape', name=name, x=x, y=y, **attrs)
    geometry(s)
    paint = node(s, 'Stroke' if stroke else 'Fill', name='Paint',
        **({'thickness': stroke, 'cap': 'round', 'join': 'round'} if stroke else {}))
    node(paint, 'SolidColor', name='Color', colorValue=color)
    return s

def rect(parent, name, x, y, w, h, radius, color):
    return shape(parent, name, lambda s: node(s, 'Rectangle', width=w, height=h,
        cornerRadiusTL=radius), color, x+w/2, y+h/2)

def ellipse(parent, name, x, y, w, h, color):
    return shape(parent, name, lambda s: node(s, 'Ellipse', width=w, height=h), color, x+w/2, y+h/2)

def path(parent, name, commands, color, stroke=0, closed=False):
    vertices = []
    for cmd in commands:
        if cmd[0] in ('M', 'L'):
            vertices.append({'p': (cmd[1], cmd[2])})
        elif cmd[0] == 'Q':
            start = vertices[-1]['p']; control = (cmd[1], cmd[2]); end = (cmd[3], cmd[4])
            vertices[-1]['out'] = tuple(start[i]+2*(control[i]-start[i])/3 for i in (0,1))
            vertices.append({'p': end, 'in': tuple(end[i]+2*(control[i]-end[i])/3 for i in (0,1))})
    def geometry(s):
        p = node(s, 'PointsPath', isClosed=str(closed).lower(), isClockwise='true', name='Path')
        for v in vertices:
            attrs = dict(x=v['p'][0], y=v['p'][1])
            if 'in' in v or 'out' in v:
                for side in ('in', 'out'):
                    target = v.get(side, v['p'])
                    dx, dy = target[0]-v['p'][0], target[1]-v['p'][1]
                    attrs[side+'Rotation'] = atan2(dy, dx)
                    attrs[side+'Distance'] = hypot(dx,dy)
                node(p, 'CubicDetachedVertex', **attrs)
            else: node(p, 'StraightVertex', **attrs)
    return shape(parent, name, geometry, color, stroke=stroke)

ink, teal = 'FF183D38', 'FF246B58'
body = node(art, 'Node', name='Paper character', x=80, y=43, scaleX=1.1, scaleY=1.1)
motion_root = body
body_center = node(body,'Node',name='Centered body motion',x=100,y=115)
pose_tilt = node(body_center, 'Node', name='Expression tilt')
body = node(pose_tilt, 'Node', name='Character artwork', x=-100, y=-115)
faces = []
wave_groups = []
arms = []
arm_paths = []
thinking = None
for index, name in enumerate(('Friendly','Excited','Curious','Proud','Wink')):
    group = node(body, 'Node', name=name+' expression', opacity=1 if index==0 else 0)
    faces.append(group)
    excited, curious, proud, wink = index==1, index==2, index==3, index==4
    if excited or proud:
        for x,y in ((28,42),(179,32)):
            path(group,'Sparkle horizontal',[('M',x-4,y),('L',x+4,y)],teal,2.5)
            path(group,'Sparkle vertical',[('M',x,y-5),('L',x,y+5)],teal,2.5)
    if curious:
        path(group,'Curious eyebrow',[('M',114,78),('Q',120,73,127,77)],ink,3)
        ellipse(group,'Thinking mouth',94,109,10,13,ink)
    elif excited:
        ellipse(group,'Tongue',90,120,17,9,'FFF1B59C')
        path(group,'Excited smile',[('M',85,109),('L',111,109),('Q',110,132,98,131),
            ('Q',86,131,85,109)],ink,closed=True)
    else:
        path(group,'Smile',[('M',86,111),('Q',98,130 if proud else 124,110,111)],ink,3.5)
    for x,closed,dy in ((72,excited or proud,2 if curious else 0),
                         (122,excited or proud,-2 if curious else 0)):
        if closed:
            path(group,'Happy eye',[('M',x-5,96+dy),('Q',x,88+dy,x+5,96+dy)],ink,4)
        else:
            eye_group = node(group,'Node',name='Blink eye',x=x,y=93.5+dy)
            eye = left_eye if x==72 else right_eye
            node(eye_group,'DataBindContext',sourcePathIds=vm.get('id')+'-'+eye.get('id'),propertyKey=17)
            wave_groups.append(eye_group)
            ellipse(eye_group,'Eye shine',-.4,-4.9,2.8,2.8,'FFFFFFFF')
            rect(eye_group,'Eye',-4,-6.5,8,13,4,ink)
    if curious:
        thinking = node(group,'Node',name='Thinking gesture',x=153,y=112)
        path(thinking,'Thinking arm',[('M',0,0),('Q',25,18,-18,20)],teal,8)
    else:
        hand = node(group,'Node',name='Waving arm',x=153,y=111)
        arm = path(hand,'Arm',[('M',0,0),('Q',19,10,26,33)],teal,8)
        arm_paths.append((index,list(arm.find('PointsPath')),'right'))
        wave_groups.append(hand)
        arms.append((index,hand,'right'))
    left = node(group,'Node',name='Left gesture',x=46,y=110)
    left_path = path(left,'Left arm',[('M',0,0),('Q',-23,15,-27,29)],teal,8)
    arm_paths.append((index,list(left_path.find('PointsPath')),'left'))
    arms.append((index,left,'left'))

path(body,'Bookmark',[('M',131,149),('L',143,149),('L',143,176),('L',137,171),('L',131,176)],teal,closed=True)
path(body,'Document line one',[('M',66,150),('L',122,150)],'FFBED18A',5)
path(body,'Document line two',[('M',66,162),('L',105,162)],'FFBED18A',5)
ellipse(body,'Left cheek',55,106,16,8,'FFE8BCA4')
ellipse(body,'Right cheek',126,106,16,8,'FFE8BCA4')
path(body,'Page highlight',[('M',48,57),('Q',49,43,64,43),('L',119,43)],'FFF2F9D4',4)
path(body,'Fold',[('M',126,32),('L',158,64),('L',138,64),('Q',126,64,126,52)],'FFBFD487',closed=True)
rect(body,'Lime paper',36,32,122,154,25,'FFE2F3A6')
rect(body,'Offset back page',46,27,119,160,26,'FFB9CE7C')
for name,commands,width in (
    ('Left leg',[('M',72,177),('L',68,201)],11),
    ('Right leg',[('M',130,177),('L',136,201)],11),
    ('Left boot',[('M',59,204),('L',74,204)],10),
    ('Right boot',[('M',131,204),('L',146,204)],10)):
    path(body,name,commands,teal,width)
shadow = ellipse(art,'Shadow',133,282,114,15,'14183D38')
shape(art,'Backdrop ring',lambda s: node(s,'Ellipse',width=248,height=248), 'FFEDF4E7',190,174,2)
ellipse(art,'Pale backdrop',48,32,284,284,'FFDCE9D6')

def keyed(animation, obj, key, values):
    target = node(animation,'KeyedObject',objectId=obj.get('id'))
    prop = node(target,'KeyedProperty',propertyKey=key)
    for frame,value in values:
        node(prop,'KeyFrameDouble',frame=frame,value=value,interpolationType='linear')

poses = []
for i,name in enumerate(('Friendly','Excited','Curious','Proud','Wink')):
    anim = node(art,'LinearAnimation',name=name,duration=1,fps=60)
    for j,group in enumerate(faces): keyed(anim,group,18,[(0,1 if i==j else 0)])
    keyed(anim,pose_tilt,15,[(0,-.08 if i==2 else 0)])
    poses.append(anim)
motions = []
for i,name in enumerate(('Greeting wave','Small celebration','Thinking gesture','Proud acknowledgment','Relaxed stretch')):
    anim = node(art,'LinearAnimation',name=name,duration=360,fps=60,loopValue='loop')
    motions.append(anim)
    vertical = [(0,43),(90,42.5),(180,43),(270,43.5),(360,43)]
    rotation = [(0,0),(360,0)]
    keyed(anim,motion_root,14,vertical)
    keyed(anim,motion_root,15,rotation)
    body_motion = [(0,0),(360,0)]
    if i==0: body_motion=[(0,0),(45,0),(85,-.012),(121,.008),(157,-.008),(195,0),(360,0)]
    elif i==2: body_motion=[(0,0),(50,-.012),(100,.012),(150,0),(360,0)]
    elif i==3: body_motion=[(0,0),(45,.015),(80,0),(110,.01),(140,0),(360,0)]
    keyed(anim,body_center,15,body_motion)
    # Reset all driven properties in every motion to keep transitions predictable.
    for expression_index,g,side in arms:
        values = [(0,0),(360,0)]
        keyed(anim,g,15,values)
    for expression_index,vertices,side in arm_paths:
        rest = (19,10,26,33) if side=='right' else (23,15,27,29)
        arm_poses = [(0,*rest),(360,*rest)]
        if expression_index==i and i==0 and side=='right':
            arm_poses = [(0,19,10,26,33),(45,19,10,26,33),
                (65,29,10,35,7),(85,26,-9,25,-29),
                (103,26,-9,18,-32),(121,26,-9,30,-26),
                (139,26,-9,18,-32),(157,26,-9,30,-26),
                (175,26,-9,25,-29),(195,29,10,35,7),
                (220,19,10,26,33),(360,19,10,26,33)]
        elif expression_index==i and i==1:
            arm_poses=[(0,*rest),(35,*rest),(75,24,2,29,-12),
                (100,24,0,28,-16),(125,24,2,29,-12),(165,*rest),(360,*rest)]
        elif expression_index==i and i==3 and side=='right':
            arm_poses=[(0,*rest),(45,20,7,5,15),(95,20,7,5,15),
                (145,*rest),(360,*rest)]
        elif expression_index==i and i==4:
            arm_poses=[(0,*rest),(50,23,8,34,8),(110,23,8,34,8),
                (160,*rest),(360,*rest)]
        # Morph shoulder tangent and wrist coordinates together, so the arm
        # unbends while lowering instead of rotating a fixed curled shape.
        for vertex,properties in ((vertices[0],(86,87)),(vertices[1],(24,25,84,85))):
            for key in properties:
                values=[]
                for frame,cx,cy,ex,ey in arm_poses:
                    if side=='left': cx,ex=-cx,-ex
                    incoming = atan2(cy-ey,cx-ex)
                    if incoming < 0: incoming += 6.283185307
                    outgoing = atan2(cy,cx)
                    # Left-arm lifts cross the +/-pi boundary. Keep its
                    # tangent continuous so interpolation cannot spin it around.
                    if side=='left' and outgoing < 0: outgoing += 6.283185307
                    data={86:outgoing,87:2*hypot(cx,cy)/3,
                        24:ex,25:ey,84:incoming,85:2*hypot(cx-ex,cy-ey)/3}
                    values.append((frame,data[key]))
                keyed(anim,vertex,key,values)
    keyed(anim,thinking,15,[(0,0),(45,.045),(75,-.03),(105,.035),(140,0),(360,0)]
        if i==2 else [(0,0)])
    for g in wave_groups:
        if g.get('name')=='Blink eye':
            base=float(g.get('x'))
            keyed(anim,g,13,[(0,base),(45,base-1.5),(90,base+1.5),(135,base),(360,base)]
                if i==2 else [(0,base)])
still = node(art,'LinearAnimation',name='Still',duration=1)
keyed(still,motion_root,14,[(0,43)])
keyed(still,motion_root,15,[(0,0)])
keyed(still,body_center,15,[(0,0)])
for g in wave_groups:
    if g.get('name')!='Blink eye': keyed(still,g,15,[(0,0)])
for _,g,side in arms:
    if side=='left': keyed(still,g,15,[(0,0)])
keyed(still,thinking,15,[(0,0)])

machine = node(art,'StateMachine',name='Mascot')
art.set('defaultStateMachineId',machine.get('id'))
def condition(transition, prop, value, boolean=False):
    c = node(transition,'TransitionViewModelCondition',opValue='equal')
    left = node(c,'TransitionPropertyViewModelComparator')
    bindable = node(left,'BindablePropertyBoolean' if boolean else 'BindablePropertyNumber')
    node(bindable,'DataBindContext',sourcePathIds=vm.get('id')+'-'+prop.get('id'),propertyKey=634 if boolean else 636)
    node(c,'TransitionValueBooleanComparator' if boolean else 'TransitionValueNumberComparator',value=value)

layer = node(machine,'StateMachineLayer',name='Expressions')
any_state = node(layer,'AnyState',x=0,y=-150)
node(layer,'ExitState',x=800,y=-150)
entry = node(layer,'EntryState',x=-180,y=0)
states = [node(layer,'AnimationState',animationId=anim.get('id'),x=i*180,y=0) for i,anim in enumerate(poses)]
node(entry,'StateTransition',stateToId=states[0].get('id'))
for i,state in enumerate(states):
    condition(node(any_state,'StateTransition',stateToId=state.get('id'),duration=180),expression,i)
layer = node(machine,'StateMachineLayer',name='Decorative motion')
any_state = node(layer,'AnyState',x=0,y=-150)
node(layer,'ExitState',x=400,y=-150)
entry = node(layer,'EntryState',x=-180,y=0)
moving = [node(layer,'AnimationState',animationId=anim.get('id'),x=i*180,y=0) for i,anim in enumerate(motions)]
stopped = node(layer,'AnimationState',animationId=still.get('id'),x=250,y=0)
node(entry,'StateTransition',stateToId=moving[0].get('id'))
for i,state in enumerate(moving):
    transition = node(any_state,'StateTransition',stateToId=state.get('id'),duration=180)
    condition(transition,motion,'true',True)
    condition(transition,expression,i)
condition(node(any_state,'StateTransition',stateToId=stopped.get('id'),duration=0),motion,'false',True)
E.indent(root)
E.ElementTree(root).write(Path(__file__).with_name('scene.rml'),encoding='utf-8',xml_declaration=True)

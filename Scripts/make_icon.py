#!/usr/bin/env python3
"""Original code-drawn Luma icon. Pillow is needed only to regenerate assets."""
from pathlib import Path
from PIL import Image, ImageDraw
import math,json
ROOT=Path(__file__).resolve().parents[1]
S=2048
im=Image.new('RGB',(S,S))
pixels=im.load()
for y in range(S):
 for x in range(S):
  glow=max(0,1-math.hypot(x-S*.45,y-S*.24)/(S*.9))
  pixels[x,y]=(int(9+14*glow),int(12+16*glow),int(28+28*glow))
mask=Image.new('L',(S,S));d=ImageDraw.Draw(mask)
def box(cx,cy,r):return tuple(int(n*2) for n in (cx-r,cy-r,cx+r,cy+r))
d.ellipse(box(500,416,210),fill=255);d.ellipse(box(594,339,204),fill=0)
moon=Image.new('RGB',(S,S),(192,178,247));im.paste(moon,(0,0),mask)
d=ImageDraw.Draw(im)
d.ellipse(box(735,244,16),fill=(247,204,141))
for index,(base,width,color) in enumerate([(697,13,(148,178,228)),(760,10,(113,140,195)),(817,7,(81,106,160))]):
 pts=[]
 for i in range(151):
  t=i/150; x=234+556*t; y=base-45*math.sin(math.pi*t)
  pts.append((x*2,y*2))
 d.line(pts,fill=color,width=width*2,joint='curve')
 for x,y in (pts[0],pts[-1]):d.ellipse((x-width,y-width,x+width,y+width),fill=color)
im=im.resize((1024,1024),Image.Resampling.LANCZOS)
assets=ROOT/'App/Resources/Assets.xcassets';assets.mkdir(exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2))
app=assets/'AppIcon.appiconset';app.mkdir(exist_ok=True)
entries=[]
for size,scales,idiom in [(20,[2,3],'iphone'),(29,[2,3],'iphone'),(40,[2,3],'iphone'),(60,[2,3],'iphone'),(1024,[1],'ios-marketing')]:
 for scale in scales:
  name=f'Icon-{size}@{scale}x.png';im.resize((size*scale,size*scale),Image.Resampling.LANCZOS).save(app/name)
  entries.append({'filename':name,'idiom':idiom,'scale':f'{scale}x','size':f'{size}x{size}'})
(app/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2))
mark=assets/'AppMark.imageset';mark.mkdir(exist_ok=True);im.save(mark/'LumaMark.png')
(mark/'Contents.json').write_text(json.dumps({'images':[{'filename':'LumaMark.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2))
print('Created opaque app icon and AppMark assets.')

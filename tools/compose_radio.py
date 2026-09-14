"""Original Night Drive score. Build dependency: NumPy 2.3.5 and ffmpeg.
No recordings, commercial music, or third-party samples.
"""
from pathlib import Path
import subprocess,tempfile,wave
import numpy as np
RATE=44100
ROOT=Path(__file__).resolve().parents[1]/'assets/audio'
TRACKS=[('neon_boulevard',103,45,80,'drive'),('last_tram',211,50,84,'drive'),('city_after_rain',307,43,76,'drive'),('tidal_station',409,48,68,'ambient'),('blue_hour',503,53,72,'ambient'),('freight_line',601,41,96,'beats'),('warehouse_sessions',701,46,92,'beats'),('home_before_dawn',809,48,88,'keys')]
def compose(name,seed,root,bpm,style):
    rng=np.random.default_rng(seed);beat=60/bpm;bars=64;duration=bars*4*beat+4
    mix=np.zeros((int(duration*RATE),2),np.float32)
    def put(v,start,gain,pan=.5):
        start=int(start*RATE);n=min(len(v),len(mix)-start)
        if n<=0:return
        mix[start:start+n,0]+=v[:n]*gain*np.sqrt(1-pan)
        mix[start:start+n,1]+=v[:n]*gain*np.sqrt(pan)
    def tone(note,seconds,kind):
        t=np.arange(int(seconds*RATE),dtype=np.float32)/RATE;freq=440*2**((note-69)/12)
        if kind=='pad':
            v=np.sin(2*np.pi*freq*t)+.32*np.sin(2*np.pi*freq*1.002*t)+.1*np.sin(2*np.pi*freq*3*t)
            env=np.minimum(t/1.3,1)*np.minimum((seconds-t)/1.8,1)
        elif kind=='bass':
            v=np.tanh((np.sin(2*np.pi*freq*t)+.24*np.sin(2*np.pi*freq*2*t))*1.3)
            env=np.minimum(t/.012,1)*np.exp(-t*2)*np.minimum((seconds-t)/.1,1)
        elif kind=='keys':
            v=np.sin(2*np.pi*freq*t+1.2*np.sin(2*np.pi*freq*2*t)*np.exp(-t*2.2))+.12*np.sin(2*np.pi*freq*3*t)
            env=np.minimum(t/.004,1)*np.exp(-t*1.8)*np.minimum((seconds-t)/.1,1)
        else:
            v=np.sin(2*np.pi*freq*t)+.25*np.sin(2*np.pi*freq*2*t)+.12*np.sin(2*np.pi*freq*3*t)
            env=np.minimum(t/.018,1)*np.exp(-t*3.8)*np.minimum((seconds-t)/.1,1)
        return (v*env).astype(np.float32)
    def drum(kind):
        t=np.arange(int(RATE*.3),dtype=np.float32)/RATE
        if kind=='kick':return np.sin(2*np.pi*(45*t+3*(1-np.exp(-t*35))))*np.exp(-t*19)
        noise=rng.uniform(-1,1,len(t)).astype(np.float32)
        noise=np.concatenate(([0],np.diff(noise))).astype(np.float32)
        return noise*np.exp(-t*(65 if kind=='hat' else 24))*(.6 if kind=='hat' else .8)
    kick=drum('kick');snare=drum('snare');hat=drum('hat')
    progression=[0,5,-3,7,0,-5,5,-3] if style=='keys' else [0,-3,5,-5,0,7,5,-3]
    motif=rng.choice([0,3,5,7,10,12,14],16)
    for bar in range(bars):
        phrase=bar//8;start=bar*4*beat;base=root+progression[(bar//2)%8]
        density=.35 if bar<8 or bar>=56 else (.65 if 32<=bar<40 else 1)
        for interval in [0,3,7,10,14]:put(tone(base+interval,4*beat+1.8,'pad'),start,.026,.2+(interval%5)*.15)
        if style!='ambient' and bar>=4:
            for b in [0,1.5,2.75]:put(tone(base-12+(7 if b==2.75 and bar%2 else 0),beat*.8,'bass'),start+b*beat,.14*density)
        if style in ['ambient','keys'] or bar>=8:
            for step in range(8):
                if style=='ambient' and step%3:continue
                if bar<8 and step%2:continue
                pitch=base+12+int(motif[(step+phrase*3)%16])
                v=tone(pitch,2.8 if style=='ambient' else 1.9,'keys' if style in ['keys','ambient'] else 'pluck')
                at=start+step*beat*.5+(.045*beat if step%2 and style=='keys' else 0)
                gain=.038*density*(.85+float(rng.random())*.3)
                put(v,at,gain,.25+(step%4)*.16);put(v,at+beat*.75,gain*.27,.85);put(v,at+beat*1.5,gain*.13,.15)
        if style!='ambient' and 8<=bar<60:
            for b in range(4):
                if style=='beats' or b%2==0:put(kick,start+b*beat,.16*density)
                if b%2==1:put(snare,start+b*beat,.035*density)
                put(hat,start+(b+.5)*beat,.019*density,.68)
                if style=='beats':put(hat,start+b*beat,.009*density,.3)
            if bar%8==7:
                for hit in range(4):put(snare,start+(3+hit*.25)*beat,.008*(hit+1)*density,.25+hit*.16)
    mix=np.tanh(mix*1.15)*.8;peak=float(np.max(np.abs(mix)));mix*=.86/max(peak,.86)
    fade=np.minimum(1,np.arange(len(mix))/RATE/3)*np.minimum(1,(len(mix)-np.arange(len(mix)))/RATE/5)
    mix*=fade[:,None];ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        wav=Path(directory)/'track.wav'
        with wave.open(str(wav),'wb') as stream:
            stream.setnchannels(2);stream.setsampwidth(2);stream.setframerate(RATE);stream.writeframes((mix*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','7','-metadata','artist=After Hours Original Score',str(ROOT/(name+'.ogg'))],check=True)
    print('RADIO',name,round(duration,2),(ROOT/(name+'.ogg')).stat().st_size,flush=True)
def prepare():
    for track in TRACKS:
        out=ROOT/(track[0]+'.ogg')
        if not out.exists() or out.stat().st_size<100000:compose(*track)
if __name__=='__main__':prepare()

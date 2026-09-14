"""Original After Hours ambient score. Optional source generator: NumPy + ffmpeg."""
import pathlib,subprocess,tempfile,wave
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
RATE=44100
SECONDS=96

def note(freq,seconds,kind='pad'):
    t=np.arange(int(RATE*seconds),dtype=np.float32)/RATE
    if kind=='pad':
        v=(np.sin(2*np.pi*freq*t)+.2*np.sin(2*np.pi*(freq*2+.07)*t)+.1*np.sin(2*np.pi*(freq*.997)*t))
        env=np.minimum(1,t/1.2)*np.minimum(1,(seconds-t)/1.8)
    else:
        v=np.sin(2*np.pi*freq*t)+.23*np.sin(2*np.pi*freq*2*t)
        env=np.minimum(1,t/.025)*np.exp(-t*2.3)*np.minimum(1,(seconds-t)/.1)
    return v*env

def compose(name,seed,root_note,sparse):
    rng=np.random.default_rng(seed);count=RATE*SECONDS;audio=np.zeros((count,2),dtype=np.float32)
    def put(v,start,amp,pan=.5):
        start=int(start*RATE);length=min(len(v),count-start)
        if length<=0:return
        audio[start:start+length,0]+=v[:length]*amp*(1-pan*.6)
        audio[start:start+length,1]+=v[:length]*amp*(.4+pan*.6)
    def hz(n):return 440*2**((n-69)/12)
    for bar in range(16):
        base=root_note+[0,-3,5,-5][bar%4]
        for n in [0,3,7,14]:put(note(hz(base+n),8),bar*6,.047,float(rng.uniform(.2,.8)))
        put(note(hz(base-12),5,'pluck'),bar*6,.085)
        for beat in range(8):
            if sparse and beat%2:continue
            pitch=base+12+[0,7,10,14,7,3,10,7][(beat+bar)%8]
            t=bar*6+beat*.75
            v=note(hz(pitch),2.5,'pluck');put(v,t,.045,float(rng.uniform(.1,.9)))
            put(v,t+.375,.013,.85);put(v,t+.75,.007,.15)
            if not sparse:
                times=np.arange(int(RATE*.24))/RATE
                kick=np.sin(2*np.pi*(42*times+10*(1-np.exp(-times*20))))*np.exp(-times*25)
                if beat%2==0:put(kick,t,.09)
                noise=rng.uniform(-1,1,int(RATE*.08)).astype(np.float32)*np.exp(-np.arange(int(RATE*.08))/RATE*95)
                put(noise,t+.375,.018)
    fade=np.minimum(1,np.arange(count)/RATE/3)*np.minimum(1,(count-np.arange(count))/RATE/4)
    audio*=fade[:,None];audio=np.clip(audio,-.85,.85)
    out=ROOT/'assets/audio'/f'{name}.ogg';out.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav=pathlib.Path(tmp)/'music.wav'
        with wave.open(str(wav),'wb') as f:
            f.setnchannels(2);f.setsampwidth(2);f.setframerate(RATE);f.writeframes((audio*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','6',str(out)],check=True)
    print(name,out.stat().st_size,flush=True)
if __name__=='__main__':
    for args in [('night_routes',17,45,False),('pine_gardens',29,48,True),('harbor_lights',51,43,True),('late_factory',83,41,False)]:compose(*args)

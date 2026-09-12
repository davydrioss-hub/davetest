extends Node
## Original synthesized sound effects and a quiet harmonic ambient bed.
var engine:AudioStreamPlayer
var ambience:AudioStreamPlayer
var rain:AudioStreamPlayer
var foot:AudioStreamPlayer
var chime:AudioStreamPlayer
var horn:AudioStreamPlayer
var step_clock=0.0
var last_position=Vector3.ZERO
var last_balance=-1
var last_horn=-1
func tone(kind:String,seconds:float,loop:bool=false) -> AudioStreamWAV:
	var rate=22050;var count=int(seconds*rate);var bytes=PackedByteArray();bytes.resize(count*2)
	var rng=RandomNumberGenerator.new();rng.seed=83
	for i in range(count):
		var t=float(i)/rate;var sample=0.0
		match kind:
			"engine":sample=(sin(TAU*55*t)*0.48+sin(TAU*110*t)*0.18+sin(TAU*165*t)*0.08+rng.randf_range(-0.04,0.04))
			"ambience":sample=(sin(TAU*110*t)+sin(TAU*164.8138*t)+sin(TAU*220*t)+sin(TAU*261.6256*t))*0.12*sin(PI*t/seconds)*sin(PI*t/seconds)
			"rain":sample=rng.randf_range(-0.22,0.22)
			"foot":sample=rng.randf_range(-0.8,0.8)*exp(-t*48)+sin(TAU*90*t)*exp(-t*30)*0.3
			"chime":sample=sin(TAU*(660 if t<0.14 else 880)*t)*exp(-fposmod(t,0.14)*22)*0.3*(1-t/seconds)
			"horn":sample=(sin(TAU*330*t)+sin(TAU*440*t))*0.2*minf(1,t*60)*minf(1,(seconds-t)*60)
		var value=int(clampf(sample,-1,1)*32700)&65535
		bytes[i*2]=value&255;bytes[i*2+1]=(value>>8)&255
	var stream=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=bytes
	if loop:stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=count
	return stream
func player(kind:String,seconds:float,loop:bool=false) -> AudioStreamPlayer:
	var p=AudioStreamPlayer.new();p.stream=tone(kind,seconds,loop);add_child(p);return p
func _ready() -> void:
	engine=player("engine",1,true);engine.volume_db=-40;engine.play()
	ambience=player("ambience",6,true);ambience.volume_db=-24;ambience.play()
	rain=player("rain",2,true);rain.volume_db=-60;rain.play()
	foot=player("foot",0.12);foot.volume_db=-22
	chime=player("chime",0.35);chime.volume_db=-14
	horn=player("horn",0.6);horn.volume_db=-12
func _process(dt:float) -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,Profile.volume)))
	ambience.volume_db=linear_to_db(maxf(0.0001,Profile.music*0.3))
	if not Session.active:engine.volume_db=-60;rain.volume_db=-60;last_balance=-1;return
	var s=Session.state();var p=s.players[Profile.player_id];var v=s.vehicles.van_01
	engine.pitch_scale=0.72+absf(v.speed)*0.075
	var near=clampf(1-WorldState.vec(p.pos).distance_to(WorldState.vec(v.pos))/23,0,1)
	engine.volume_db=linear_to_db(maxf(0.0001,near*(0.07 if v.driver!="" else 0.0)))
	rain.volume_db=-26 if s.economy.weather.rain else -60
	var pos=WorldState.vec(p.pos);step_clock+=dt
	if p.vehicle=="" and p.alive and pos.distance_to(last_position)>dt*0.4 and step_clock>0.36:foot.play();step_clock=0
	last_position=pos
	if last_balance>=0 and int(s.economy.company.balance)>last_balance:chime.play()
	last_balance=int(s.economy.company.balance)
	if int(v.get("horn_tick",-1))>last_horn:
		last_horn=int(v.horn_tick)
		if near>0:horn.play()

"""Exercise real ENet peers. Usage: python tests/network_tests.py /path/to/godot."""
from __future__ import annotations
import json, os, pathlib, shutil, socket, subprocess, sys, tempfile, time

PROJECT = pathlib.Path(__file__).resolve().parents[1]
GODOT = str(pathlib.Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else 'godot'
ROOT = pathlib.Path(tempfile.mkdtemp(prefix='after-hours-network-'))
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.bind(('127.0.0.1', 0))
    PORT = s.getsockname()[1]
BOTS = []
CHECKS = []

def wait(predicate, description, timeout=18):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                CHECKS.append(description)
                print('PASS', description, flush=True)
                return value
        except (KeyError, FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(.1)
    raise AssertionError(description)

class Bot:
    def __init__(self, name, role='client', password='crew', load=False, profile=None):
        self.name=name
        self.path=profile or ROOT/name
        self.path.mkdir(parents=True, exist_ok=True)
        for f in ['state.json', 'command.json']:
            (self.path/f).unlink(missing_ok=True)
        self.serial=0
        self.logpath=ROOT/(name+'.log')
        self.log=open(self.logpath,'w')
        self.proc=subprocess.Popen([GODOT,'--headless','--path',str(PROJECT),
            'res://tests/bot.tscn','--',f'--profile-dir={self.path}',f'--role={role}',
            f'--nickname={name}',f'--port={PORT}',f'--password={password}',f'--load={str(load).lower()}'],
            stdout=self.log,stderr=subprocess.STDOUT)
        BOTS.append(self)
    def state(self):
        return json.loads((self.path/'state.json').read_text())
    def command(self, **kwargs):
        self.serial+=1
        p=self.path/'command.tmp'
        p.write_text(json.dumps({'id':self.serial,**kwargs}))
        p.replace(self.path/'command.json')
    def action(self, action, target=''):
        self.command(actions=[{'action':action,'target':target}])
    def stop(self):
        if self.proc.poll() is None:
            self.command(quit=True)
            try:self.proc.wait(timeout=4)
            except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()
    @property
    def id(self):return self.state()['id']

def world(bot):return bot.state()['world']
def connected(bot):return bot.state()['active']
def player(bot, id=None):return world(bot)['players'][id or bot.id]

try:
    host=Bot('host','host')
    wait(lambda:connected(host),'Host starts and plays')
    clients=[Bot('client'+str(i)) for i in range(1,8)]
    wait(lambda:all(connected(c) for c in clients),'Eight simultaneous players complete handshake')
    wait(lambda:sum(p['connected'] for p in world(host)['players'].values())==8,'Host counts eight authenticated players')
    wait(lambda:all(len(world(c)['players'])==8 for c in clients),'All late joiners have the same eight players')
    overflow=Bot('overflow')
    wait(lambda:'Server is full' in overflow.state()['message'],'Ninth player is rejected')
    overflow.stop()
    bad=Bot('wrong-password',password='wrong')
    wait(lambda:'Incorrect password' in bad.state()['message'],'Wrong password rejected')
    bad.stop()
    a,b=clients[:2]
    start=player(host,a.id)['pos'][0]
    a.command(move=[1,0])
    wait(lambda:player(host,a.id)['pos'][0]>start+1,'Movement intent changes server position')
    a.command(move=[0,0])
    wait(lambda:abs(player(b,a.id)['pos'][0]-player(host,a.id)['pos'][0])<.3,'Movement replicates to another client')
    # Test-only host positioning isolates race/validation checks from navigation.
    loc=world(host)['items']['parcel_01']['pos']
    host.command(teleport={a.id:loc,b.id:loc})
    wait(lambda:abs(player(a)['pos'][0]-loc[0])<.8,'Reliable teleport reaches client')
    a.action('pickup','parcel_01');b.action('pickup','parcel_01')
    wait(lambda:world(host)['items']['parcel_01']['holder'] in [a.id,b.id],'Simultaneous pickup resolves on server')
    holder=world(host)['items']['parcel_01']['holder']
    winner=a if a.id==holder else b
    loser=b if winner is a else a
    wait(lambda:sum('parcel_01' in p['inventory'] for p in world(host)['players'].values())==1,'No duplicate item after race')
    wait(lambda:world(loser)['items']['parcel_01']['holder']==holder,'Pickup ownership replicates')
    winner.action('complete_order','order_01')
    wait(lambda:'Bring the parcel' in winner.state()['message'],'Remote order cannot complete at wrong location')
    host.command(teleport={holder:[12,0,-6]})
    wait(lambda:player(winner)['pos'][0]==12,'Dispatch position synchronized')
    winner.action('complete_order','order_01')
    wait(lambda:player(host,holder)['money']==550,'Server pays valid order once')
    winner.action('complete_order','order_01')
    wait(lambda:'already completed' in winner.state()['message'],'Repeated request rejected over network')
    assert player(host,holder)['money']==550
    winner.action('add_money','999999')
    wait(lambda:'Unknown action' in winner.state()['message'],'Invented money RPC action rejected')
    assert player(host,holder)['money']==550
    # Keep an item through disconnect and save/load, in addition to money/stats.
    loc=world(host)['items']['parcel_02']['pos']
    host.command(teleport={holder:loc})
    wait(lambda:abs(player(winner)['pos'][0]-loc[0])<.1,'Second parcel location synchronized')
    winner.action('pickup','parcel_02')
    wait(lambda:'parcel_02' in player(host,holder)['inventory'],'Durable item acquired')
    profile=winner.path
    winner.stop()
    wait(lambda:not player(host,holder)['connected'],'Client departure saves offline player')
    restored=Bot('reconnected',profile=profile)
    wait(lambda:connected(restored),'Same local PlayerID reconnects')
    wait(lambda:restored.id==holder and player(restored)['money']==550 and 'parcel_02' in player(restored)['inventory'] and player(restored)['stats']['deliveries']==1,'Reconnect restores inventory, money and stats')
    duplicate_dir=ROOT/'duplicate-profile'
    duplicate_dir.mkdir()
    shutil.copy(profile/'identity.key',duplicate_dir/'identity.key')
    duplicate=Bot('duplicate',profile=duplicate_dir)
    wait(lambda:'already connected' in duplicate.state()['message'],'Duplicate identity cannot displace a player')
    duplicate.stop()
    wid=world(host)['world_id']
    host.command(save=True)
    wait(lambda:(host.path/'Saves/NetworkTest/world.sav').exists(),'Host save file exists')
    assert not (restored.path/'Saves').exists(), 'Client must never create world saves'
    CHECKS.append('Client stores no host world save');print('PASS Client stores no host world save',flush=True)
    host.stop()
    wait(lambda:not connected(restored) and restored.state()['message']=='Host disconnected.','Host exit closes session with explicit reason')
    for c in clients+[restored]:c.stop()
    host2=Bot('host-reloaded','host',load=True,profile=host.path)
    wait(lambda:connected(host2),'Host loads saved world')
    restored2=Bot('client-reloaded',profile=profile)
    wait(lambda:connected(restored2),'Client rejoins reloaded world')
    wait(lambda:world(restored2)['world_id']==wid and player(restored2)['money']==550 and 'parcel_02' in player(restored2)['inventory'],'Save/load retains world identity and progress')
    restored2.stop();host2.stop()
    empty_host=Bot('no-password-host','host',password='')
    wait(lambda:connected(empty_host),'Host starts without a password')
    empty_client=Bot('no-password-client',password='')
    wait(lambda:connected(empty_client),'Optional empty password works end to end')
    pos=player(empty_host,empty_client.id)['pos'][:]
    empty_client.command(move=[1000000,1000000])
    wait(lambda:empty_client.state()['command_id']==1,'Oversized movement request sent')
    time.sleep(.5)
    assert player(empty_host,empty_client.id)['pos']==pos, 'Malformed input must never move player'
    CHECKS.append('Oversized movement is rejected');print('PASS Oversized movement is rejected',flush=True)
    empty_host.proc.kill();empty_host.proc.wait()
    wait(lambda:not connected(empty_client) and empty_client.state()['message']=='Host disconnected.','Abrupt host termination is detected',timeout=40)
    empty_client.stop()
    for bot in BOTS:
        bot.log.flush()
        content=bot.logpath.read_text()
        if 'SCRIPT ERROR' in content or '\nERROR:' in content:
            raise AssertionError(f'Engine error in {bot.logpath}:\n{content[:2000]}')
    print(f'NETWORK TESTS: {len(CHECKS)} passed; real ENet host + 7 clients',flush=True)
    (PROJECT/'tests'/'last_network_result.json').write_text(json.dumps({'checks':CHECKS,'count':len(CHECKS)},indent=2))
except Exception:
    print('Diagnostics:',ROOT,flush=True)
    for b in BOTS:
        b.log.flush()
        text=b.logpath.read_text()
        if 'ERROR' in text:print(b.name,text[-3000:],flush=True)
    raise
finally:
    for bot in BOTS:
        if bot.proc.poll() is None:bot.proc.kill();bot.proc.wait()
        bot.log.close()

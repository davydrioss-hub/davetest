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
        deadline=time.monotonic()+6
        while time.monotonic()<deadline:
            if self.proc.poll() is not None:return
            try:
                if self.state()['command_id']>=self.serial:return
            except (FileNotFoundError,KeyError,json.JSONDecodeError):pass
            time.sleep(.03)
        raise AssertionError('Bot did not consume command: '+self.name)
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
    a.action('accept_order','d001_01')
    wait(lambda:world(host)['orders']['d001_01']['status']=='active','Client accepts authoritative contract')
    iid=world(host)['orders']['d001_01']['item']
    loc=world(host)['items'][iid]['pos']
    host.command(teleport={a.id:loc,b.id:loc})
    wait(lambda:abs(player(a)['pos'][0]-loc[0])<.1 and abs(player(b)['pos'][0]-loc[0])<.1,'Both couriers synchronize at cargo')
    a.action('pickup',iid);b.action('pickup',iid)
    wait(lambda:world(host)['items'][iid]['holder'] in [a.id,b.id],'Simultaneous pickup resolves once')
    holder=world(host)['items'][iid]['holder']
    winner=a if a.id==holder else b
    loser=b if winner is a else a
    wait(lambda:sum(iid in p['inventory'] for p in world(host)['players'].values())==1,'No duplicated cargo after race')
    winner.action('complete_order','d001_01')
    wait(lambda:'отмеченному адресу' in winner.state()['message'],'Delivery distance enforced remotely')
    rear=[-34,0,25.9]
    host.command(teleport={holder:rear})
    wait(lambda:abs(player(winner)['pos'][0]+34)<.1,'Driver reaches rear door')
    winner.action('cargo_door')
    wait(lambda:world(host)['vehicles']['van_01']['door_open'],'Rear door opens for whole session')
    winner.action('load')
    wait(lambda:iid in world(host)['vehicles']['van_01']['cargo'] and iid not in player(host,holder)['inventory'],'Loading moves cargo without duplication')
    winner.action('secure')
    wait(lambda:world(loser)['items'][iid]['secured'],'Cargo straps replicate to observer')
    loser.action('unload',iid)
    wait(lambda:'задней двери' in loser.state()['message'],'Remote stealing from van rejected')
    winner.action('unload',iid)
    wait(lambda:iid in player(host,holder)['inventory'] and not world(host)['vehicles']['van_01']['cargo'],'Unloading conserves cargo on server')
    host.command(teleport={holder:[-16,0,-8]})
    wait(lambda:abs(player(winner)['pos'][0]+16)<.1,'Destination synchronizes')
    winner.action('complete_order','d001_01')
    wait(lambda:world(host)['economy']['company']['balance']==1000,'Company receives validated payment')
    wait(lambda:world(loser)['orders']['d001_01']['status']=='completed','Delivery completion replicates')
    winner.action('complete_order','d001_01')
    wait(lambda:'активного заказа' in winner.state()['message'],'Repeat payment rejected')
    assert world(host)['economy']['company']['balance']==1000
    winner.action('add_money','999999')
    wait(lambda:'Неизвестное действие' in winner.state()['message'],'Invented reward action rejected')
    # Both clients buy the same upgrade; only one debit and one installation.
    host.command(teleport={holder:[-43,0,16],loser.id:[-43,0,16]})
    wait(lambda:abs(player(winner)['pos'][2]-16)<.1 and abs(player(loser)['pos'][2]-16)<.1,'Crew reaches upgrade terminal')
    winner.action('upgrade','capacity');loser.action('upgrade','capacity')
    wait(lambda:world(host)['vehicles']['van_01']['capacity']==10,'Capacity upgrade installs')
    wait(lambda:world(winner)['economy']['company']['balance']==200 and world(loser)['economy']['company']['balance']==200,'Concurrent purchase debits company once')
    loser.action('end_shift')
    wait(lambda:'Only the host' in loser.state()['message'],'Client cannot end the shared shift')
    # Four synchronized seats; passenger input cannot move the van.
    driver=clients[2]
    riders=clients[2:6]
    host.command(teleport={c.id:[-34,0,29] for c in riders+[clients[6]]})
    wait(lambda:all(abs(player(c)['pos'][0]+34)<.1 for c in riders),'Riders arrive')
    driver.action('cargo_door')
    wait(lambda:not world(host)['vehicles']['van_01']['door_open'],'Cargo door closes')
    for c in riders:
        c.action('vehicle','van_01')
        wait(lambda c=c:player(host,c.id)['vehicle']=='van_01','Passenger boards '+c.name)
    clients[6].action('vehicle','van_01')
    wait(lambda:'четыре места' in clients[6].state()['message'],'Fifth vehicle occupant rejected')
    wait(lambda:len(world(winner)['vehicles']['van_01']['passengers'])==4,'Four vehicle seats replicate')
    old=world(host)['vehicles']['van_01']['pos'][:]
    riders[1].command(move=[0,-1]);time.sleep(.4);riders[1].command(move=[0,0])
    assert world(host)['vehicles']['van_01']['pos']==old
    CHECKS.append('Passenger movement cannot drive');print('PASS Passenger movement cannot drive',flush=True)
    for c in riders:
        c.action('vehicle','van_01')
        wait(lambda c=c:player(host,c.id)['vehicle']=='','Passenger exits '+c.name)
    # Keep cargo and stats through disconnect, save/load, and a new snapshot.
    winner.action('accept_order','d001_02')
    wait(lambda:world(host)['orders']['d001_02']['status']=='active','Second contract accepted')
    iid2=world(host)['orders']['d001_02']['item']
    loc=world(host)['items'][iid2]['pos']
    host.command(teleport={holder:loc})
    wait(lambda:abs(player(winner)['pos'][0]-loc[0])<.1,'Second cargo position synchronized')
    winner.action('pickup',iid2)
    wait(lambda:iid2 in player(host,holder)['inventory'],'Durable cargo acquired')
    profile=winner.path;winner.stop()
    wait(lambda:not player(host,holder)['connected'],'Departure retains offline player')
    restored=Bot('reconnected',profile=profile)
    wait(lambda:connected(restored),'Same local PlayerID reconnects')
    wait(lambda:restored.id==holder and iid2 in player(restored)['inventory'] and player(restored)['stats']['deliveries']==1 and world(restored)['economy']['company']['balance']==200,'Reconnect restores cargo, company and personal progress')
    duplicate_dir=ROOT/'duplicate-profile';duplicate_dir.mkdir();shutil.copy(profile/'identity.key',duplicate_dir/'identity.key')
    duplicate=Bot('duplicate',profile=duplicate_dir)
    wait(lambda:'already connected' in duplicate.state()['message'],'Duplicate identity cannot displace player');duplicate.stop()
    wid=world(host)['world_id'];host.command(save=True)
    wait(lambda:(host.path/'Saves/NetworkTest/world.sav').exists(),'Host save exists')
    assert not (restored.path/'Saves').exists()
    CHECKS.append('Client has no world save');print('PASS Client has no world save',flush=True)
    host.stop()
    wait(lambda:not connected(restored) and restored.state()['message']=='Host disconnected.','Host departure explicitly ends session')
    for c in clients+[restored]:c.stop()
    host2=Bot('host-reloaded','host',load=True,profile=host.path)
    wait(lambda:connected(host2),'Host loads persistent world')
    restored2=Bot('client-reloaded',profile=profile)
    wait(lambda:connected(restored2),'Client joins reloaded world')
    wait(lambda:world(restored2)['world_id']==wid and iid2 in player(restored2)['inventory'] and world(restored2)['vehicles']['van_01']['capacity']==10,'Save/load preserves world, cargo and upgrades')
    host2.command(teleport={host2.id:[-43,0,16]})
    wait(lambda:abs(player(host2)['pos'][2]-16)<.1,'Host reaches shift terminal')
    host2.action('end_shift')
    wait(lambda:world(restored2)['economy']['shift']['status']=='finished','Shift report replicates to client')
    host2.action('next_shift')
    wait(lambda:world(restored2)['economy']['shift']['day']==2 and not world(restored2)['items'] and len(world(restored2)['orders'])==10 and not player(restored2)['inventory'],'Next night reliably deletes prior cargo and preserves world')
    assert world(restored2)['world_id']==wid
    restored2.stop();host2.stop()
    empty_host=Bot('no-password-host','host',password='')
    wait(lambda:connected(empty_host),'Host starts without password')
    empty_client=Bot('no-password-client',password='')
    wait(lambda:connected(empty_client),'Optional empty password handshake works')
    pos=player(empty_host,empty_client.id)['pos'][:]
    empty_client.command(move=[1000000,1000000])
    wait(lambda:empty_client.state()['command_id']==1,'Malformed movement sent');time.sleep(.4)
    assert player(empty_host,empty_client.id)['pos']==pos
    CHECKS.append('Oversized movement rejected');print('PASS Oversized movement rejected',flush=True)
    empty_host.proc.kill();empty_host.proc.wait()
    wait(lambda:not connected(empty_client) and empty_client.state()['message']=='Host disconnected.','Abrupt host termination detected',timeout=40)
    empty_client.stop()
    for bot in BOTS:
        bot.log.flush();content=bot.logpath.read_text()
        if 'SCRIPT ERROR' in content or '\nERROR:' in content:raise AssertionError(f'Engine error in {bot.logpath}:\n{content[:2000]}')
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

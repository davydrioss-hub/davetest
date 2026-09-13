"""Launch the exported Windows EXE itself and verify an actual host save."""
import argparse,json,pathlib,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('exe');args=p.parse_args()
exe=pathlib.Path(args.exe).resolve()
with tempfile.TemporaryDirectory(prefix='after-hours-win-') as temp:
    profile=pathlib.Path(temp)
    result=subprocess.run([str(exe),'--headless','--log-file',str(profile/'game.log'),'--quit-after','180','--','--demo',f'--profile-dir={profile}'],cwd=exe.parent,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding="utf-8",errors="replace",timeout=90)
    log=(profile/'game.log').read_text(encoding='utf-8')
    print(result.stdout+log)
    assert result.returncode==0, result.returncode
    assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log
    saves=list(profile.glob('Saves/*/world.sav'));assert len(saves)==1,'Exported game did not create a host world'
    world=json.loads(json.loads(saves[0].read_text(encoding='utf-8'))['payload'])
    assert world['format']==3 and len(world['orders'])==30 and len(world['players'])==1
    assert world['vehicles']['van_01']['capacity']==6 and len(world['vehicles'])==3
    assert len(world['activities'])==15 and world['economy']['company']['chapter']==0
    assert not world['vehicles']['courier_02']['owned'] and not world['employees']['dispatcher']['hired']
    print('WINDOWS EXE SMOKE: native process starts, creates company, jobs, player and host save')

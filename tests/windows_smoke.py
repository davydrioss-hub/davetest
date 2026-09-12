"""Launch the exported Windows EXE itself and verify an actual host save."""
import argparse,json,pathlib,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('exe');args=p.parse_args()
exe=pathlib.Path(args.exe).resolve()
with tempfile.TemporaryDirectory(prefix='after-hours-win-') as temp:
    profile=pathlib.Path(temp)
    result=subprocess.run([str(exe),'--headless','--quit-after','180','--','--demo',f'--profile-dir={profile}'],cwd=exe.parent,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
    print(result.stdout)
    assert result.returncode==0, result.returncode
    assert 'SCRIPT ERROR' not in result.stdout and '\nERROR:' not in result.stdout
    saves=list(profile.glob('Saves/*/world.sav'));assert len(saves)==1,'Exported game did not create a host world'
    world=json.loads(json.loads(saves[0].read_text())['payload'])
    assert world['format']==2 and len(world['orders'])==10 and len(world['players'])==1
    assert world['vehicles']['van_01']['capacity']==6
    print('WINDOWS EXE SMOKE: native process starts, creates company, jobs, player and host save')

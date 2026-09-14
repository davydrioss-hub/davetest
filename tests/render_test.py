"""Real graphics and input smoke under a desktop or Xvfb."""
import os,pathlib,subprocess,sys,tempfile
engine=pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='after-hours-render-') as profile:
    result=subprocess.run([str(engine),'--audio-driver','Dummy','--rendering-method',sys.argv[2],'--path','.', 'res://tests/render_smoke.tscn','--',f'--profile-dir={profile}'],capture_output=True,text=True,timeout=300)
    print(result.stdout+result.stderr)
    assert result.returncode==0
    assert 'SCRIPT ERROR' not in result.stdout+result.stderr and '\nERROR:' not in result.stdout+result.stderr
    assert 'RENDER SMOKE:' in result.stdout and '/ '+sys.argv[2] in result.stdout

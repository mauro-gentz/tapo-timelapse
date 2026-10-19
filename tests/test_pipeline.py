import unittest
from pathlib import Path

class TestPipeline(unittest.TestCase):
    def test_pipeline_with_fake_camera_and_cloud(self):
        import os,subprocess,tempfile,pathlib,datetime,shutil,json
        from pathlib import Path
        pkg=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as td:
         root=Path(td); bindir=root/'bin'; bindir.mkdir(); datadir=root/'data'; datadir.mkdir()
         (root/'rclone.conf').write_text('fake config')
         fake_schedule=bindir/'tapo-schedule'; fake_schedule.write_text('''#!/bin/bash
        case "$1" in
        next) echo 2040-01-01T00:00:00Z;;
        due) date -u +%Y/%m/%d/%Y-%m-%d_00-00-00Z;;
        sync|init) :;;
        expected) echo '["00:00"]';;
        esac
        '''); fake_schedule.chmod(0o755)
         fake_notify=bindir/'tapo-notify'; fake_notify.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "'+str(root/'mailcalls')+'"\ncat >/dev/null || :\n');fake_notify.chmod(0o755)
         fake_rclone=bindir/'rclone'; fake_rclone.write_text('''#!/bin/bash
        printf "%s\\n" "$*" >> "'''+str(root/'calls')+'''"
        if [[ -f "'''+str(root/'fail')+'''" ]]; then exit 1; fi
        exit 0
        ''');fake_rclone.chmod(0o755)
         fake_ffmpeg=bindir/'ffmpeg'; fake_ffmpeg.write_text('''#!/bin/bash
        out="${@: -1}"
        printf 'FAKEPNG' > "$out"
        ''');fake_ffmpeg.chmod(0o755)
         fake_ffprobe=bindir/'ffprobe'; fake_ffprobe.write_text('#!/bin/bash\necho 2304x1296\n');fake_ffprobe.chmod(0o755)
         testscript=root/'tapo-timelapse'; script=(pkg/'tapo-timelapse').read_text().replace('/usr/local/bin/tapo-schedule',str(fake_schedule)).replace('/usr/local/bin/tapo-notify',str(fake_notify)).replace('/usr/local/bin/tapo-health',str(pkg/'tapo-health'));testscript.write_text(script);testscript.chmod(0o755)
         config=root/'test.conf';config.write_text(f'''CAMERA_HOST='192.168.1.2'
        CAMERA_USER='test'
        CAMERA_PASSWORD='test'
        CAMERA_STREAM='stream1'
        RCLONE_CONFIG='{root}/rclone.conf'
        RCLONE_REMOTE='onedrive'
        DATA_DIR='{datadir}'
        RCLONE_ROOT='Timelapse/Grundstueck'
        MONITOR_EMAIL_ENABLED='no'
        CAPTURE_INTERVAL_MINUTES='20'
        UPLOAD_AFTER_CAPTURE='yes'
        ''')
         env=os.environ.copy();env.update(TAPO_CONFIG=str(config),PATH=f'{bindir}:'+env['PATH'])
         def run(*args):
          return subprocess.run([str(testscript),*args],text=True,capture_output=True,env=env)
         today=datetime.datetime.now(datetime.timezone.utc).strftime('%Y/%m/%d'); dd=datadir/today; dd.mkdir(parents=True);f=dd/'example.png';f.write_bytes(b'1234')
         r=run('upload');assert r.returncode==0,r.stderr;assert 'OneDrive upload successful' in r.stdout,r.stdout
         assert len((root/'calls').read_text().splitlines())==1
         r=run('upload');assert r.returncode==0,r.stderr;assert len((root/'calls').read_text().splitlines())==1,'duplicate transfer'
         f.write_bytes(b'1234567');r=run('upload');assert r.returncode==0,r.stderr;assert len((root/'calls').read_text().splitlines())==2,'missing retransfer'
         (root/'fail').write_text('fail'); f2=dd/'missing.png';f2.write_bytes(b'missing');r=run('upload');assert r.returncode==1,'failure not propagated';assert f2.exists();assert not (datadir/'.uploaded'/today/'missing.png.ok').exists()
         (root/'fail').unlink();r=run('upload');assert r.returncode==0;assert (datadir/'.uploaded'/today/'missing.png.ok').exists()
         r=run('capture');assert r.returncode==0,(r.stdout,r.stderr);assert 'Saved:' in r.stdout and 'OneDrive upload successful:' in r.stdout
         print('Upload, retry, receipt, capture, sequential flow tested successfully')

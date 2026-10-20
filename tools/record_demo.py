"""Record the real bounded demo commands as an asciicast and a standalone HTML player.

Run only after the application is RUNNING. Always attempts a graceful stop.
No credentials or environment dumps are recorded. AWS and application responses
are captured after each command completes, with their actual elapsed timestamps.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', default='clickstream')
    parser.add_argument('--dataset', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--reconcile-only', action='store_true')
    parser.add_argument('--publish-receipt', type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    cast = args.out / 'demo.cast'
    if cast.exists():
        raise ValueError('recording already exists; preserve earlier evidence')
    started = time.monotonic()
    events = []
    def emit(value):
        events.append([round(time.monotonic()-started, 3), 'o', value.replace('\n', '\r\n')])
        print(value, end='', flush=True)
    def run(command):
        emit('$ ' + ' '.join(map(str, command)) + '\n')
        result = subprocess.run(command, capture_output=True, text=True, timeout=600)
        emit(result.stdout + result.stderr)
        emit(f'[exit {result.returncode}]\n\n')
        if result.returncode:
            raise RuntimeError(f'Command failed with exit {result.returncode}')
    cli = [sys.executable, '-m', 'clickstream.cli', '--profile', args.profile]
    try:
        manifest = json.loads((args.dataset/'manifest.json').read_text())
        emit('Reproducible synthetic clickstream demo\n')
        emit(json.dumps({k:v for k,v in manifest.items() if k!='expected_rows'}, indent=2)+'\n\n')
        run(['aws','kinesisanalyticsv2','describe-application','--application-name','clickstream-dev-pipeline','--profile',args.profile,'--region','us-west-2','--query','ApplicationDetail.{Status:ApplicationStatus,Runtime:RuntimeEnvironment}','--no-cli-pager'])
        if args.reconcile_only:
            if args.publish_receipt is None:
                raise ValueError('reconcile-only requires the original acknowledgement receipt')
            receipt = json.loads(args.publish_receipt.read_text())
            expected = dict(status='ACKNOWLEDGED', run_id=manifest['run_id'], sha256=manifest['sha256'], acknowledged_records=manifest['event_count'])
            if any(receipt.get(key) != value for key, value in expected.items()):
                raise ValueError('original receipt does not match this dataset')
            emit('Original acknowledgement verified; publication skipped.\n')
            emit(json.dumps(receipt, indent=2)+'\n\n')
        else:
            run(cli + ['publish','--dataset',str(args.dataset),'--stream','clickstream-dev-events','--receipt',str(args.out/'publish-receipt.json')])
        run(cli + ['reconcile','--dataset',str(args.dataset),'--workgroup','clickstream-dev-demo','--out',str(args.out/'athena-verification.json')])
    finally:
        try:
            run(cli + ['stop'])
        finally:
            header = dict(version=2,width=130,height=36,timestamp=int(time.time()),title='Actual clickstream v0.1 command capture')
            cast.write_text('\n'.join(json.dumps(x) for x in [header]+events)+'\n')
            payload = json.dumps(events).replace('<', '\\u003c')
            document = '''<!doctype html><html lang="en"><meta charset="utf-8"><title>Clickstream v0.1 actual demo</title><style>body{background:#0c1422;color:#dce8fa;font:16px monospace;margin:30px}button,select{font:inherit;padding:8px}pre{white-space:pre-wrap;line-height:1.4;border:1px solid #45556c;padding:20px}small{color:#afc4df}</style><h1>Actual clickstream command capture</h1><p>Commands and responses from the real AWS run. Output is shown when each command completed. No cloud success is inferred from the recording alone.</p><button id="play">Play / restart</button> <select id="speed"><option value="1">1× actual elapsed time</option><option value="5">5×</option><option value="20">20×</option></select><pre id="terminal"></pre><script>const events=PAYLOAD;let timer;document.getElementById('play').onclick=()=>{clearInterval(timer);const out=document.getElementById('terminal');out.textContent='';let index=0;const start=performance.now();const speed=Number(document.getElementById('speed').value);timer=setInterval(()=>{const elapsed=(performance.now()-start)/1000*speed;while(index<events.length&&events[index][0]<=elapsed){out.textContent+=events[index++][2];}if(index===events.length)clearInterval(timer);},50);};</script></html>'''.replace('PAYLOAD', payload)
            (args.out/'demo.html').write_text(document)
    return 0


if __name__ == '__main__':
    sys.exit(main())

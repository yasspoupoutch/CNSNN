#!/usr/bin/env python3
"""Prints the useful part of an iOS crash report (.ips): the exception, the crashed thread's frames
(the app's own first) and any assertion message. Usage: crash_summary.py REPORT.ips"""
import json, sys

text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
header, _, body = text.partition('\n')
report = json.loads(body)
print('Exception :', json.dumps(report.get('exception', {}), ensure_ascii=False))
print('Termination :', json.dumps(report.get('termination', {}), ensure_ascii=False)[:1500])
for key in ('asi', 'lastExceptionBacktrace'):
    if key in report:
        print(key, ':', json.dumps(report[key], ensure_ascii=False)[:3000])
images = report.get('usedImages', [])
for thread in report.get('threads', []):
    if not thread.get('triggered'):
        continue
    print('Fil planté :', thread.get('name') or thread.get('queue') or '')
    for frame in thread.get('frames', [])[:40]:
        image = images[frame['imageIndex']]['name'] if frame.get('imageIndex', -1) < len(images) else '?'
        print(f"  {image:<28} {frame.get('symbol', '?')} {frame.get('sourceFile', '')}:{frame.get('sourceLine', '')}")

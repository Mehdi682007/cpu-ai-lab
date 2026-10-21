"""HTTP integration tests against the real handler, mocking only Ollama."""
import http.client
import importlib.util
import io
import json
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

spec=importlib.util.spec_from_file_location('cpu_ai_chat',Path(__file__).resolve().parents[1]/'src'/'chat.py')
app=importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
seen=[]
entered=threading.Event();release=threading.Event()
completion_reason="length"; completion_count=512
class Upstream(io.BytesIO):
    def __init__(self,payload):
        self.payload=payload
        events=[{'message':{'content':'<script>alert(1)</script>\n```css\nleft'}},
                {'message':{'content':': 50%;\n```'},'done':True,'done_reason':completion_reason,
                 'eval_count':completion_count,'eval_duration':2000000000}]
        super().__init__(''.join(json.dumps(e)+'\n' for e in events).encode())
    def __enter__(self):
        if self.payload['messages'][-1]['content']=='SLOW':entered.set();release.wait(10)
        return self

def fake_urlopen(request,timeout=None):
    if isinstance(request,str):return io.BytesIO(json.dumps({'models':[{'name':app.MODEL}]}).encode())
    payload=json.loads(request.data);seen.append(payload);return Upstream(payload)
app.urllib.request.urlopen=fake_urlopen
server=ThreadingHTTPServer(('127.0.0.1',0),app.Handler)
port=server.server_port
app.ALLOWED_HOSTS=(f'127.0.0.1:{port}',f'localhost:{port}')
threading.Thread(target=server.serve_forever,daemon=True).start()
def call(path='/',body=None,headers=None):
    conn=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
    data=json.dumps(body).encode() if body is not None else None
    conn.request('POST' if body is not None else 'GET',path,data,headers or {'Content-Type':'application/json'})
    response=conn.getresponse();status=response.status;raw=response.read();conn.close();return status,raw
base={'messages':[{'role':'user','content':'Build a splash screen'}],'mode':'code','max_tokens':2048}
status,raw=call('/chat',base);assert status==200
rows=[json.loads(line) for line in raw.splitlines()]
assert rows[-1]['done'] and rows[-1]['truncated'] and rows[-1]['tokens']==512
assert seen[-1]['options']['num_predict']==2048 and seen[-1]['options']['num_ctx']==4096
assert seen[-1]['options']['num_batch']==128 and seen[-1]['options']['num_gpu']==0
assert '<script>' in rows[0]['token'] # frontend must render this as text, not HTML
print('PASS: long-output configuration and explicit truncation event')
assert rows[-1]['tokens_per_second']==256 and rows[-1]['wall_seconds']>=0
for completion_reason,completion_count,expected in [(None,2048,True),(None,100,False),('stop',2048,False)]:
    status,raw=call('/chat',base);assert status==200
    event=json.loads(raw.splitlines()[-1]);assert event['truncated'] is expected
    assert event['max_tokens']==2048 and event['tokens']==completion_count
completion_reason='length';completion_count=512
print('PASS: timing metrics and legacy completion-limit detection without mislabeling normal stops')

continuation={'messages':[{'role':'user','content':'Build CSS'},{'role':'assistant','content':'```css\nleft'},
                         {'role':'user','content':'Continue exactly'}], 'continuing':True,'max_tokens':1024}
assert call('/chat',continuation)[0]==200
assert any(m['content']=='```css\nleft' for m in seen[-1]['messages'])
print('PASS: continuation preserves the previous partial code')
too_long=dict(continuation);too_long['messages']=[{'role':'user','content':'Build CSS'},
    {'role':'assistant','content':'x'*20000},{'role':'user','content':'Continue'}]
before=len(seen);assert call('/chat',too_long)[0]==400 and len(seen)==before
print('PASS: continuation is rejected instead of silently dropping its source')
assert call('/chat',{'messages':[]})[0]==400
assert call('/chat',dict(base,max_tokens=-1))[0]==400
assert call('/chat',base,{'Content-Type':'application/json','Origin':'https://example.com'})[0]==403
assert call('/config',headers={'Host':'attacker.example'})[0]==403
print('PASS: invalid input, Origin and Host rejected')
result=[]
def slow():result.append(call('/chat',{'messages':[{'role':'user','content':'SLOW'}]}))
t=threading.Thread(target=slow);t.start();assert entered.wait(5)
assert call('/chat',base)[0]==429
release.set();t.join(10);assert result and result[0][0]==200
print('PASS: CPU inference concurrency is limited to one request')
assert call('/health')[0]==200
import hashlib
app.AUTH={'username':'admin','salt':'11'*16,'password_hash':hashlib.pbkdf2_hmac('sha256',b'test-only-password',bytes.fromhex('11'*16),310000).hex()}
def authcall(path,body=None,cookie=None,extra=None):
    conn=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
    headers={'Content-Type':'application/json'}
    if cookie:headers['Cookie']=cookie
    headers.update(extra or {})
    conn.request('POST' if body is not None else 'GET',path,json.dumps(body).encode() if body is not None else None,headers)
    r=conn.getresponse();result=(r.status,dict(r.getheaders()),r.read());conn.close();return result
assert authcall('/config')[0]==401
before=len(seen);assert authcall('/chat',base)[0]==401 and len(seen)==before
assert authcall('/login',{'username':'admin','password':'wrong'})[0]==401
status,headers,_=authcall('/login',{'username':'admin','password':'test-only-password'},extra={'X-Forwarded-Proto':'https'})
assert status==200
cookie=headers['Set-Cookie'].split(';',1)[0]
assert 'HttpOnly' in headers['Set-Cookie'] and 'Secure' in headers['Set-Cookie'] and 'SameSite=Strict' in headers['Set-Cookie']
assert authcall('/config',cookie=cookie)[0]==200
assert authcall('/chat',base,cookie=cookie)[0]==200
assert authcall('/logout',{},cookie=cookie)[0]==200
assert authcall('/config',cookie=cookie)[0]==401
for _ in range(8):assert authcall('/login',{'username':'admin','password':'wrong'})[0]==401
assert authcall('/login',{'username':'admin','password':'wrong'})[0]==429
print('PASS: login required, secure session, logout invalidation and login throttling')
server.shutdown();server.server_close()
print('ALL HTTP INTEGRATION CHECKS PASSED')

#!/usr/bin/env python3
"""CPU AI Lab 0.3: bounded, loopback-only streaming chat."""
import hashlib
import hmac
import secrets
from collections import deque
from http.cookies import SimpleCookie
import json
import math
import os
import threading
import time
import urllib.request
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = '0.3.3'
MODEL = os.environ.get('CPU_AI_MODEL', 'qwen2.5:1.5b')
THREADS = max(1, int(os.environ.get('CPU_AI_THREADS', '2')))
CONTEXT = max(2048, min(8192, int(os.environ.get('CPU_AI_CONTEXT', '4096'))))
LOCK = threading.Lock()
PORT = int(os.environ.get('CPU_AI_WEB_PORT', '5555'))
PUBLIC_HOST = os.environ.get('CPU_AI_PUBLIC_HOST', '')
ALLOWED_HOSTS = (f'127.0.0.1:{PORT}', f'localhost:{PORT}') + ((PUBLIC_HOST,) if PUBLIC_HOST else ())
AUTH_PATH = os.environ.get('CPU_AI_AUTH_FILE', '')
AUTH = json.loads(Path(AUTH_PATH).read_text()) if AUTH_PATH else None
SESSIONS = {}
LOGIN_FAILURES = deque(maxlen=8)
AUTH_LOCK = threading.Lock()
LOGIN_PAGE = Path(__file__).with_name('login.html').read_bytes()
PAGE = Path(__file__).with_name('index.html').read_bytes()

# A conservative estimate, not a tokenizer. Always disclose when history is trimmed.
def estimate(messages):
    total = 0
    for message in messages:
        content = message['content']
        ascii_count = sum(ord(c) < 128 for c in content)
        total += math.ceil(ascii_count / 2.5 + (len(content)-ascii_count)*1.5) + 24
    return total

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, status, body, content_type='application/json; charset=utf-8'):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(body)

    def discard_body(self):
        try:
            size = int(self.headers.get('Content-Length','0'))
            if 0 < size <= 160000:
                self.connection.settimeout(2)
                self.rfile.read(size)
        except (ValueError,TimeoutError,OSError):
            pass

    def reject(self, status, body):
        self.discard_body()
        return self.send(status, body)

    def valid_host(self):
        return self.headers.get('Host', '') in ALLOWED_HOSTS

    def origin_ok(self):
        origin = self.headers.get('Origin')
        if origin is None:
            return True
        allowed = {f'http://127.0.0.1:{PORT}', f'http://localhost:{PORT}'}
        if PUBLIC_HOST:
            allowed.add('https://' + PUBLIC_HOST)
        return origin in allowed

    def session(self):
        if AUTH is None:
            return True
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get('Cookie', ''))
            token = cookie['cpu_ai_session'].value
        except Exception:
            return False
        now = time.monotonic()
        with AUTH_LOCK:
            for key in list(SESSIONS):
                if SESSIONS[key] <= now:
                    del SESSIONS[key]
            return token if token in SESSIONS else False

    def login(self):
        if AUTH is None:
            return self.send(404, {'error':'Login is not enabled'})
        now = time.monotonic()
        with AUTH_LOCK:
            while LOGIN_FAILURES and now - LOGIN_FAILURES[0] > 60:
                LOGIN_FAILURES.popleft()
            if len(LOGIN_FAILURES) >= 8:
                return self.reject(429, {'error':'تلاش‌های ناموفق زیاد است؛ یک دقیقه بعد دوباره تلاش کنید.'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                raise ValueError()
            self.connection.settimeout(15)
            body = json.loads(self.rfile.read(size))
            username, password = body['username'], body['password']
            if not isinstance(username,str) or not isinstance(password,str) or len(password)>1024:
                raise ValueError()
            calculated = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(AUTH['salt']),310000).hex()
            valid = hmac.compare_digest(username.encode(), AUTH['username'].encode()) and hmac.compare_digest(calculated,AUTH['password_hash'])
        except (ValueError,KeyError,TypeError,TimeoutError):
            return self.send(400, {'error':'درخواست نامعتبر است.'})
        if not valid:
            with AUTH_LOCK:
                LOGIN_FAILURES.append(now)
            return self.send(401, {'error':'نام کاربری یا رمز ورود درست نیست.'})
        token = secrets.token_urlsafe(32)
        with AUTH_LOCK:
            if len(SESSIONS) >= 32:
                SESSIONS.pop(next(iter(SESSIONS)))
            SESSIONS[token] = now+28800
            LOGIN_FAILURES.clear()
        secure = '; Secure' if self.headers.get('X-Forwarded-Proto') == 'https' else ''
        self.send_response(200)
        self.send_header('Set-Cookie','cpu_ai_session='+token+'; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800'+secure)
        self.send_header('Cache-Control','no-store')
        self.send_header('Content-Length','2')
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(b'{}')

    def do_GET(self):
        if not self.valid_host():
            return self.send(403, {'error': 'Invalid host'})
        if self.path == '/':
            return self.send(200, PAGE if self.session() else LOGIN_PAGE, 'text/html; charset=utf-8')
        if self.path == '/config':
            if not self.session():
                return self.send(401, {'error':'لطفاً وارد شوید.'})
            return self.send(200, {'model': MODEL, 'version': VERSION, 'cpu_only': True,
                       'context': CONTEXT, 'output_choices': [512, 1024, 2048], 'default_output': 1024, 'auth_enabled': AUTH is not None})
        if self.path == '/health':
            try:
                with urllib.request.urlopen('http://127.0.0.1:11434/api/tags', timeout=5) as response:
                    models = json.load(response).get('models', [])
                if MODEL not in [model['name'] for model in models]:
                    raise RuntimeError('Missing model')
                return self.send(200, {'status': 'ready', 'model': MODEL, 'version': VERSION, 'busy': LOCK.locked()})
            except Exception:
                return self.send(503, {'error': 'Model unavailable', 'version': VERSION})
        return self.send(404, {'error': 'Not found'})

    def do_POST(self):
        if not self.valid_host():
            return self.reject(403, {'error': 'Invalid host'})
        if not self.origin_ok():
            return self.reject(403, {'error': 'Cross-origin request rejected'})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.reject(415, {'error': 'JSON required'})
        if self.path == '/login':
            return self.login()
        if not self.session():
            return self.reject(401, {'error':'نشست ورود تمام شده است. صفحه را دوباره باز کنید.'})
        if self.path == '/logout':
            self.discard_body()
            token = self.session()
            with AUTH_LOCK:
                SESSIONS.pop(token, None)
            self.send_response(200)
            self.send_header('Set-Cookie','cpu_ai_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
            self.send_header('Content-Length','2')
            self.end_headers()
            self.wfile.write(b'{}')
            return
        if self.path != '/chat':
            return self.reject(404, {'error':'Not found'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 160000:
                return self.send(413, {'error': 'متن درخواست بیش از حد طولانی است.'})
            self.connection.settimeout(20)
            body = json.loads(self.rfile.read(size))
            messages = body['messages']
            output = body.get('max_tokens', 1024)
            mode = body.get('mode', 'general')
            continuing = body.get('continuing', False)
            if type(continuing) is not bool:
                raise ValueError()
            if type(output) is not int or output not in (512, 1024, 2048) or mode not in ('general', 'code'):
                raise ValueError()
            if not isinstance(messages, list) or not 1 <= len(messages) <= 12:
                raise ValueError()
            for message in messages:
                if not isinstance(message, dict) or message['role'] not in ('user', 'assistant'):
                    raise ValueError()
                if not isinstance(message['content'], str) or not 0 < len(message['content']) <= 24000:
                    raise ValueError()
            if messages[-1]['role'] != 'user':
                raise ValueError()
            system = 'Answer directly and accurately. If unsure, say so. Follow the requested language and length. Avoid repetition.'
            if mode == 'code':
                system += ' For code requests, give complete runnable code in fenced code blocks. Keep explanation short. Do not use filler. Never claim code was tested.'
            fitted = [dict(role=m['role'], content=m['content']) for m in messages]
            trimmed = 0
            budget = CONTEXT - output - 256
            while len(fitted) > (3 if continuing else 2) and estimate(fitted) + estimate([{'role':'system','content':system}]) > budget:
                fitted.pop(0)
                trimmed += 1
                if fitted and fitted[0]['role'] == 'assistant':
                    fitted.pop(0)
                    trimmed += 1
            if estimate(fitted) + estimate([{'role':'system','content':system}]) > budget:
                return self.send(400, {'error': 'متن برای طول پاسخ انتخاب‌شده زیاد است. پاسخ کوتاه‌تر انتخاب کنید یا گفت‌وگوی جدید بسازید.'})
        except (ValueError, KeyError, TypeError, TimeoutError):
            return self.send(400, {'error': 'درخواست نامعتبر است.'})
        if not LOCK.acquire(blocking=False):
            return self.send(429, {'error': 'مدل مشغول است؛ کمی بعد دوباره تلاش کنید.'})
        streaming = False
        start = time.monotonic()
        first = None
        try:
            payload = {'model': MODEL, 'messages': [{'role': 'system', 'content': system}] + fitted,
                       'stream': True, 'keep_alive': '5m', 'options': {'num_gpu': 0,
                       'num_thread': THREADS, 'num_ctx': CONTEXT, 'num_batch': 128,
                       'num_predict': output, 'temperature': 0.1 if mode == 'code' else 0.2}}
            if MODEL.startswith('qwen3'):
                payload['think'] = False
            request = urllib.request.Request('http://127.0.0.1:11434/api/chat', json.dumps(payload).encode(),
                                             {'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=1200) as response:
                self.send_response(200)
                self.send_header('Content-Type', 'application/x-ndjson; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                streaming = True
                completed = False
                for line in response:
                    data = json.loads(line)
                    if 'error' in data:
                        raise RuntimeError(data['error'])
                    token = data.get('message', {}).get('content', '')
                    if token and first is None:
                        first = time.monotonic() - start
                    event = {'token': token}
                    if data.get('done'):
                        completed = True
                        duration = data.get('eval_duration', 0)/1e9
                        event.update(done=True, tokens=data.get('eval_count', 0),
                            tokens_per_second=data.get('eval_count', 0)/duration if duration else 0,
                            truncated=(data.get('done_reason') == 'length' or
                                       (not data.get('done_reason') and data.get('eval_count', 0) >= output)),
                            done_reason=data.get('done_reason', 'stop'), context_trimmed=trimmed,
                            ttft_seconds=round(first, 2) if first is not None else None,
                            wall_seconds=round(time.monotonic()-start, 2), max_tokens=output)
                    self.wfile.write((json.dumps(event, ensure_ascii=False)+'\n').encode())
                    self.wfile.flush()
                if not completed:
                    raise RuntimeError('Incomplete upstream stream')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            error = {'error': 'ارتباط با مدل قطع شد یا زمان پردازش تمام شد. متن دریافت‌شده حفظ شده است؛ می‌توانید دوباره تلاش کنید.'}
            try:
                if streaming:
                    self.wfile.write((json.dumps(error, ensure_ascii=False)+'\n').encode())
                    self.wfile.flush()
                else:
                    self.send(502, error)
            except OSError:
                pass
        finally:
            LOCK.release()

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()

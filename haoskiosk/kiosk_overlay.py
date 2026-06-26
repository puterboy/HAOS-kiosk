#!/usr/bin/env python3
# On-screen "back to the Wall" button for chromium kiosk-out pages.
# Watches the DevTools port; when chromium is on a non-dashboard page (a game or
# an external site like Maps/Earth) it injects a fixed, always-visible back button
# into the DOM. Tapping it returns to the dashboard. No-op on the Wall itself.
# Consistent across every kiosk-out target; composited in-page (no extra X window).
import socket, base64, os, json, struct, time, urllib.request

HA   = os.environ.get("HA_URL", "http://127.0.0.1:8123").rstrip("/")
DASH = os.environ.get("HA_DASHBOARD", "").lstrip("/")
PORT = int(os.environ.get("REMOTE_DEBUG_PORT", "9222"))
DASH_URL = HA + "/" + DASH if DASH else HA + "/"

INJECT = """(function(){
  var onWall = location.href.indexOf('%URL%') === 0;
  var b = document.getElementById('wall-kiosk-back');
  if (onWall) { if (b) b.remove(); return 'wall'; }
  if (b) return 'exists';
  b = document.createElement('div');
  b.id = 'wall-kiosk-back';
  b.setAttribute('style','position:fixed;top:50%;left:18px;transform:translateY(-50%);z-index:2147483647;'+
    'background:#0E1116;color:#fff;font:700 22px/1 Lato,Segoe UI,Arial,sans-serif;'+
    'padding:18px 24px;display:flex;align-items:center;gap:12px;cursor:pointer;'+
    'letter-spacing:.04em;box-shadow:0 3px 14px rgba(0,0,0,.55);user-select:none;'+
    '-webkit-tap-highlight-color:transparent;');
  b.innerHTML = '<span style="font-size:30px;font-weight:400;line-height:1">&#8249;</span><span>WALL</span>';
  b.addEventListener('click', function(){ location.href = '%URL%'; });
  (document.body || document.documentElement).appendChild(b);
  return 'added';
})();""".replace('%URL%', DASH_URL)

def recvn(s,n):
    b=b""
    while len(b)<n:
        c=s.recv(n-len(b))
        if not c: break
        b+=c
    return b
def ws_connect(path):
    s=socket.create_connection(("127.0.0.1",PORT),timeout=5)
    k=base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {k}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    r=b""
    while b"\r\n\r\n" not in r: r+=s.recv(4096)
    return s
def ws_send(s,o):
    d=json.dumps(o).encode(); n=len(d); m=os.urandom(4); h=bytearray([0x81])
    if n<126: h.append(0x80|n)
    elif n<65536: h.append(0x80|126); h+=struct.pack(">H",n)
    else: h.append(0x80|127); h+=struct.pack(">Q",n)
    h+=m; s.sendall(bytes(h)+bytes(b^m[i%4] for i,b in enumerate(d)))
def ws_recv(s):
    b0=recvn(s,1)
    if not b0: return None
    op=b0[0]&0x0f; l=recvn(s,1)[0]&0x7f
    if l==126: l=struct.unpack(">H",recvn(s,2))[0]
    elif l==127: l=struct.unpack(">Q",recvn(s,8))[0]
    p=recvn(s,l)
    if op in (0x8,0x9): return (("close" if op==0x8 else "ping"), p)
    return ("text", p.decode("utf-8","replace"))
def evaluate(wsurl, expr):
    s=ws_connect(wsurl.split(str(PORT),1)[1])
    try:
        ws_send(s,{"id":1,"method":"Runtime.evaluate","params":{"expression":expr,"returnByValue":True}})
        while True:
            r=ws_recv(s)
            if r is None or r[0]=="close": return None
            if r[0]!="text": continue
            o=json.loads(r[1])
            if o.get("id")==1: return o
    finally:
        try: s.close()
        except Exception: pass

def page_info():
    ts=json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=3))
    p=next((t for t in ts if t.get("type")=="page"), None)
    return (p.get("url","") if p else "", p.get("webSocketDebuggerUrl","") if p else "")

# wait for the debug port, then watch + inject
for _ in range(60):
    try:
        if page_info()[1]: break
    except Exception: pass
    time.sleep(1)
while True:
    try:
        url, wsurl = page_info()
        if wsurl and url.startswith(("http://","https://")) and not url.startswith(DASH_URL):
            res = evaluate(wsurl, INJECT)
            val = ((res or {}).get('result') or {}).get('result', {}).get('value')
            if val and val != 'exists':
                print('[overlay]', val, url, flush=True)
    except Exception:
        pass
    time.sleep(1)

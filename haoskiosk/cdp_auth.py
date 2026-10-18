#!/usr/bin/env python3
# Self-healing kiosk auth for the chromium browser option.
# Waits for the DevTools port; if chromium is on a login page, mints a session
# token over the trusted loopback (trusted_networks) and injects it into
# localStorage so the dashboard loads authenticated. No-op when already authed.
import socket, base64, os, json, struct, time, urllib.request, urllib.parse, sys

HA   = os.environ.get("HA_URL", "http://127.0.0.1:8123").rstrip("/")
DASH = os.environ.get("HA_DASHBOARD", "").lstrip("/")
PORT = int(os.environ.get("REMOTE_DEBUG_PORT", "9222"))
DASH_URL = HA + "/" + DASH if DASH else HA + "/"
CLIENT = HA + "/"

def log(*a): print("[cdp_auth]", *a, flush=True)

def targets():
    return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=3))

page = None
for _ in range(60):
    try:
        page = next((t for t in targets() if t.get("type") == "page"), None)
        if page: break
    except Exception: pass
    time.sleep(1)
if not page:
    log("DevTools never came up; giving up"); sys.exit(0)

def current_url():
    try:
        return next((t.get("url","") for t in targets() if t.get("type")=="page"), "")
    except Exception: return ""

need = False
for _ in range(8):
    u = current_url()
    if "/auth/authorize" in u or "/auth/login" in u:
        need = True; break
    time.sleep(1)
if not need:
    log("already authenticated; nothing to do"); sys.exit(0)
log("login page detected; authenticating via trusted loopback")

def post(url, data, form=False):
    if form:
        body = urllib.parse.urlencode(data).encode(); ct = "application/x-www-form-urlencoded"
    else:
        body = json.dumps(data).encode(); ct = "application/json"
    return json.load(urllib.request.urlopen(urllib.request.Request(url, body, {"Content-Type": ct}), timeout=5))

try:
    flow = post(HA+"/auth/login_flow", {"client_id":CLIENT,"handler":["trusted_networks",None],"redirect_uri":CLIENT})
    code = flow.get("result")
    if not code:
        log("trusted_networks unavailable; form-fill fallback not implemented"); sys.exit(0)
    tok = post(HA+"/auth/token", {"grant_type":"authorization_code","code":code,"client_id":CLIENT}, form=True)
except Exception as e:
    log("token mint failed:", e); sys.exit(0)

hass = {
 "access_token": tok["access_token"], "token_type": tok.get("token_type","Bearer"),
 "refresh_token": tok["refresh_token"], "expires_in": tok.get("expires_in",1800),
 "ha_auth_provider": tok.get("ha_auth_provider","trusted_networks"),
 "expires": int(time.time()*1000) + tok.get("expires_in",1800)*1000,
 "clientId": CLIENT, "hassUrl": HA,
}

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
def cmd(s,i,method,params=None):
    ws_send(s,{"id":i,"method":method,"params":params or {}})
    while True:
        r=ws_recv(s)
        if r is None or r[0]=="close": return None
        if r[0]!="text": continue
        try: o=json.loads(r[1])
        except: continue
        if o.get("id")==i: return o

try:
    path = page["webSocketDebuggerUrl"].split(str(PORT),1)[1]
    s = ws_connect(path)
    cmd(s,1,"Page.enable")
    cmd(s,2,"Page.navigate",{"url":CLIENT})
    time.sleep(3)
    expr = "localStorage.setItem('hassTokens', %s); 'ok'" % json.dumps(json.dumps(hass))
    cmd(s,3,"Runtime.evaluate",{"expression":expr,"returnByValue":True})
    cmd(s,4,"Page.navigate",{"url":DASH_URL})
    log("authenticated; navigated to", DASH_URL)
except Exception as e:
    log("CDP inject failed:", e)
sys.exit(0)

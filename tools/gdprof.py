#!/usr/bin/env python3
"""Profiles a running game from outside the editor: a minimal Godot 4 remote-debugger server
that switches on the script, servers and visual (GPU) profilers and, when the game quits,
prints the GDScript functions by self and total time per frame, the physics/audio servers'
times, and the GPU time of each render pass.

    python3 tools/gdprof.py [port] [--skip=SECONDS] > report.txt &
    godot --path . --remote-debug tcp://127.0.0.1:6007 -- --autotest procedural 1 --perf

--skip ignores the first seconds (loading). Uses only the standard library."""
import socket, struct, sys, time, collections

PORT = 6007
SKIP = 8.0
for a in sys.argv[1:]:
    if a.startswith("--skip="):
        SKIP = float(a[7:])
    elif a.isdigit():
        PORT = int(a)


class R:
    def __init__(s, b):
        s.b, s.p = b, 0

    def u32(s):
        v = struct.unpack_from("<I", s.b, s.p)[0]; s.p += 4; return v

    def i32(s):
        v = struct.unpack_from("<i", s.b, s.p)[0]; s.p += 4; return v

    def take(s, n):
        v = s.b[s.p:s.p + n]; s.p += n; return v


def dec(r):
    h = r.u32()
    t = h & 0xFF
    f64 = h & (1 << 16)
    if t == 0: return None
    if t == 1: return bool(r.u32())
    if t == 2:
        return struct.unpack("<q", r.take(8))[0] if f64 else r.i32()
    if t == 3:
        return struct.unpack("<d", r.take(8))[0] if f64 else struct.unpack("<f", r.take(4))[0]
    if t in (4, 21, 22):   # String, StringName, NodePath (as its string)
        n = r.u32(); s = r.take(n).decode("utf8", "replace"); r.take((4 - n % 4) % 4); return s
    fsz = 8 if f64 else 4
    ff = "<d" if f64 else "<f"
    nfl = {5: 2, 6: 2, 7: 4, 8: 4, 9: 3, 10: 3, 11: 6, 12: 4, 13: 4, 14: 4, 15: 4, 16: 6, 17: 9, 18: 12, 19: 16, 20: 4}
    if t in nfl:
        if t in (6, 8, 10, 13):
            return [r.i32() for _ in range(nfl[t])]
        if t == 20:
            return [struct.unpack("<f", r.take(4))[0] for _ in range(4)]
        return [struct.unpack(ff, r.take(fsz))[0] for _ in range(nfl[t])]
    if t == 23: return r.take(8)
    if t == 24:
        if f64:
            return ("obj", struct.unpack("<Q", r.take(8))[0])
        cls = dec_str(r)
        if cls == "": return None
        n = r.u32(); props = {}
        for _ in range(n):
            k = dec_str(r); props[k] = dec(r)
        return (cls, props)
    if t == 27:
        tk = (h >> 16) & 3; tv = (h >> 18) & 3
        _typed(r, tk); _typed(r, tv)
        n = r.u32() & 0x7FFFFFFF
        d = {}
        for _ in range(n):
            k = dec(r); d[repr(k) if isinstance(k, list) else k] = dec(r)
        return d
    if t == 28:
        _typed(r, (h >> 16) & 3)
        n = r.u32() & 0x7FFFFFFF
        return [dec(r) for _ in range(n)]
    if t == 29:
        n = r.u32(); v = r.take(n); r.take((4 - n % 4) % 4); return v
    if t == 30:
        n = r.u32(); return list(struct.unpack("<%di" % n, r.take(4 * n)))
    if t == 31:
        n = r.u32(); return list(struct.unpack("<%dq" % n, r.take(8 * n)))
    if t == 32:
        n = r.u32(); return list(struct.unpack("<%df" % n, r.take(4 * n)))
    if t == 33:
        n = r.u32(); return list(struct.unpack("<%dd" % n, r.take(8 * n)))
    if t == 34:
        n = r.u32(); return [dec_str(r) for _ in range(n)]
    if t in (35, 36, 37, 38):
        k = {35: 2, 36: 3, 37: 4, 38: 4}[t]
        if t == 37: fs, fm = 4, "<f"
        else: fs, fm = fsz, ff
        n = r.u32(); return [[struct.unpack(fm, r.take(fs))[0] for _ in range(k)] for _ in range(n)]
    if t in (25, 26):
        return None
    raise ValueError("variant type %d" % t)


def _typed(r, kind):
    if kind == 1: r.u32()
    elif kind in (2, 3): dec_str(r)


def dec_str(r):
    n = r.u32(); s = r.take(n).decode("utf8", "replace"); r.take((4 - n % 4) % 4); return s


def enc(v):
    if v is None: return struct.pack("<I", 0)
    if isinstance(v, bool): return struct.pack("<II", 1, int(v))
    if isinstance(v, int): return struct.pack("<Iq", 2 | (1 << 16), v)
    if isinstance(v, float): return struct.pack("<Id", 3 | (1 << 16), v)
    if isinstance(v, str):
        b = v.encode(); return struct.pack("<II", 4, len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)
    if isinstance(v, list):
        return struct.pack("<II", 28, len(v)) + b"".join(enc(x) for x in v)
    raise TypeError(v)


def send(c, msg, data):
    b = enc([msg, 1, data])
    c.sendall(struct.pack("<I", len(b)) + b)


def recv_exact(c, n):
    out = b""
    while len(out) < n:
        k = c.recv(n - len(out))
        if not k: raise EOFError
        out += k
    return out


sigs = {}
self_t = collections.Counter()
tot_t = collections.Counter()
calls = collections.Counter()
frames = 0
servers = collections.Counter()
srv_frames = 0
unknown = collections.Counter()
vis_cpu = collections.Counter(); vis_gpu = collections.Counter(); vis_frames = [0]

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT)); srv.listen(1)
print("listening", PORT, file=sys.stderr)
c, _ = srv.accept()
t0 = None
enabled = False
try:
    while True:
        n = struct.unpack("<I", recv_exact(c, 4))[0]
        msg = dec(R(recv_exact(c, n)))
        name, data = msg[0], msg[2]
        if t0 is None:
            t0 = time.time()
        if not enabled and time.time() - t0 > 0.5:
            send(c, "profiler:servers", [True, [512, False]])
            send(c, "profiler:scripts", [True, [512, False]])
            send(c, "profiler:visual", [True])
            enabled = True
        if name == "debug_enter":
            print("DEBUG BREAK:", data, file=sys.stderr)
            send(c, "continue", [])
        elif name == "servers:function_signature":
            sigs[data[1]] = data[0]
        elif name == "servers:profile_frame":
            if time.time() - t0 < SKIP:
                continue
            d = data
            # frame_number, frame_time, process_time, physics_time, physics_frame_time, script_time, servers..., funcs
            i = 6
            nsrv = d[i]; i += 1
            for _ in range(nsrv):
                sname = d[i]; nf = d[i + 1]; i += 2
                for k in range(nf // 2):
                    servers[sname + "/" + str(d[i])] += d[i + 1]; i += 2
            srv_frames += 1
            nfn = d[i]; i += 1
            rest = d[i:]
            # entries: sig, calls, total, self, internal  (5 each) -- detect stride
            stride = 5 if nfn and len(rest) % 5 == 0 and (nfn % 5 == 0) else 4
            cnt = nfn // stride
            for k in range(cnt):
                e = rest[k * stride:(k + 1) * stride]
                sid, cc, st, tt = e[0], e[1], e[2], e[3]
                calls[sid] += cc; tot_t[sid] += tt; self_t[sid] += st
            frames += 1
        elif name == "visual:profile_frame":
            if time.time() - t0 < SKIP:
                continue
            # frame_number, then [name, cpu_ms, gpu_ms] triples flattened
            d = data
            try:
                arr = d[2:]
                marks = [(arr[k], arr[k + 1], arr[k + 2]) for k in range(0, len(arr) - 2, 3)]
                vis_cpu["~FRAME TOTAL"] += marks[-1][1] - marks[0][1]
                vis_gpu["~FRAME TOTAL"] += marks[-1][2] - marks[0][2]
                vp = ""
                for k in range(len(marks) - 1):
                    nm = marks[k][0]
                    if nm.startswith("> Render Viewport"):
                        vp = nm[9:]
                    key = vp + " | " + nm
                    vis_cpu[key] += marks[k + 1][1] - marks[k][1]
                    vis_gpu[key] += marks[k + 1][2] - marks[k][2]
            except Exception as ex:
                print("vis parse", ex, file=sys.stderr)
            vis_frames[0] += 1
        elif name in ("output", "error", "stack_dump"):
            if name == "error":
                print("ERR", data[:8], file=sys.stderr)
        else:
            unknown[name] += 1
except (EOFError, ConnectionResetError):
    pass

print("frames profiled:", frames, "unknown msgs:", dict(unknown))
if frames:
    print("\n== script functions by SELF time (ms/frame) ==")
    for sid, v in self_t.most_common(45):
        print("%7.3f self %7.3f total %8.1f calls/f  %s" % (v * 1000 / frames, tot_t[sid] * 1000 / frames, calls[sid] / frames, sigs.get(sid, sid)))
    print("\n== by TOTAL time ==")
    for sid, v in tot_t.most_common(30):
        print("%7.3f total %7.3f self %8.1f calls/f  %s" % (v * 1000 / frames, self_t[sid] * 1000 / frames, calls[sid] / frames, sigs.get(sid, sid)))
if srv_frames:
    print("\n== servers (ms/frame) ==")
    for k, v in servers.most_common(30):
        print("%7.3f %s" % (v * 1000 / srv_frames, k))

if vis_frames[0]:
    print("\n== visual (ms/frame, cpu / gpu) ==")
    for k, v in vis_gpu.most_common(40):
        print("%7.3f cpu %7.3f gpu  %s" % (vis_cpu[k] / vis_frames[0], v / vis_frames[0], k))

<#
  The syscall-level payload for the Guard 4 ground-truth probe.

  READ-ONLY WITH RESPECT TO THE PRODUCT. Everything it creates lives under
  /var/tmp. It marks paths, counts events and answers permission requests. It
  installs nothing, changes no product file and starts no product service.

  WHY ONE FILE RATHER THAN SEVEN
  ------------------------------
  Every question below is the same three syscalls asked a different way:
  fanotify_init, fanotify_mark, and a read/write on the resulting fd. Splitting
  them across phases would mean seven copies of the constant table, and a
  constant that is wrong in one copy and right in the others is the kind of
  defect that reads as a kernel answer. So the constants exist once, and each
  phase invokes a subcommand.

  WHY PYTHON AND ctypes RATHER THAN A COMPILED HELPER
  ---------------------------------------------------
  The work-package preference, and it is the right one for a reason worth
  writing down: if this probe needed a compiler, then Guard 4 would need to ship
  one, or ship a prebuilt binary per kernel it might meet. Establishing that the
  syscalls are reachable from an interpreter that is already on the box is
  therefore part of the answer, not a convenience. If python3 turns out to be
  absent the phase says so and records it as a bundling finding rather than
  quietly apt-installing its way to a green result.

  THE ONE HAZARD THIS FILE HAS TO RESPECT
  ---------------------------------------
  A permission-mode fanotify group that stops answering does not fail open. Every
  process that opens a marked path blocks until the group is closed or the kernel
  times it out. So every daemon here has a hard deadline, closes its group on the
  way out, and never touches the tree it is watching. A probe that wedges the box
  it is measuring produces no evidence and costs a VM.
#>

$G4Py = @'
#!/usr/bin/env python3
"""Guard 4 ground-truth probe. Subcommands are documented in main()."""

import ctypes
import errno
import json
import os
import select
import shutil
import struct
import sys
import time

libc = ctypes.CDLL("libc.so.6", use_errno=True)

# --- fanotify constants, from linux/fanotify.h -----------------------------
FAN_CLOEXEC = 0x00000001
FAN_NONBLOCK = 0x00000002
FAN_CLASS_NOTIF = 0x00000000
FAN_CLASS_CONTENT = 0x00000004

FAN_MODIFY = 0x00000002
FAN_CLOSE_WRITE = 0x00000008
FAN_OPEN = 0x00000020
FAN_OPEN_PERM = 0x00010000
FAN_ACCESS_PERM = 0x00020000

FAN_MARK_ADD = 0x00000001
FAN_MARK_REMOVE = 0x00000002
FAN_MARK_MOUNT = 0x00000010
FAN_MARK_IGNORED_MASK = 0x00000020
FAN_MARK_IGNORED_SURV_MODIFY = 0x00000040
FAN_MARK_FILESYSTEM = 0x00000100

FAN_EVENT_ON_CHILD = 0x08000000

FAN_ALLOW = 0x01
FAN_DENY = 0x02

AT_FDCWD = -100
METADATA_LEN = 24  # event_len u32, vers u8, reserved u8, metadata_len u16, mask u64, fd s32, pid s32

libc.fanotify_init.restype = ctypes.c_int
libc.fanotify_init.argtypes = [ctypes.c_uint, ctypes.c_uint]
libc.fanotify_mark.restype = ctypes.c_int
libc.fanotify_mark.argtypes = [
    ctypes.c_int, ctypes.c_uint, ctypes.c_uint64, ctypes.c_int, ctypes.c_char_p
]


def emit(obj):
    """One JSON object per line, prefixed so a PowerShell phase can find it in
    a transcript that also carries free text."""
    sys.stdout.write("G4JSON " + json.dumps(obj) + "\n")
    sys.stdout.flush()


def fan_init(flags, event_flags=os.O_RDONLY):
    fd = libc.fanotify_init(flags, event_flags)
    if fd < 0:
        e = ctypes.get_errno()
        return -1, e, errno.errorcode.get(e, str(e))
    return fd, 0, "OK"


def fan_mark(fd, flags, mask, path):
    rc = libc.fanotify_mark(fd, flags, mask, AT_FDCWD, path.encode())
    if rc < 0:
        e = ctypes.get_errno()
        return False, e, errno.errorcode.get(e, str(e))
    return True, 0, "OK"


def read_event(fd, timeout):
    """Return (mask, event_fd, pid) or None on timeout."""
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        return None
    buf = os.read(fd, METADATA_LEN * 32)
    if len(buf) < METADATA_LEN:
        return None
    event_len, vers, _res, _mlen, mask, evfd, pid = struct.unpack("=IBBHQii", buf[:METADATA_LEN])
    return (mask, evfd, pid, vers)


def respond(fd, event_fd, verdict):
    """Answer a permission event. Returns the number of bytes written.

    The byte count is the evidence that the verdict was ISSUED rather than
    merely decided. L30.1: a fault injection that does not inject scores a
    false pass, and 'the daemon intended to deny' is exactly that shape.
    """
    return os.write(fd, struct.pack("=iI", event_fd, verdict))


def fd_path(event_fd):
    try:
        return os.readlink("/proc/self/fd/%d" % event_fd)
    except OSError:
        return "(unresolvable)"


# ---------------------------------------------------------------- perm ------
def cmd_perm(marked, unmarked, delay):
    """Question 1. Does the kernel WAIT for a root daemon's answer and HONOUR it?

    Three measurements in one run:
      allow  -- the opener must be observed to block for `delay`
      deny   -- the opener must fail with EPERM, and the deny must be shown issued
      free   -- a file outside the mark opens normally, proving the mark is what
                is doing the work rather than something else being broken
    """
    out = {"cmd": "perm", "marked": marked, "unmarked": unmarked, "delay": delay}

    fd, e, ename = fan_init(FAN_CLOEXEC | FAN_CLASS_CONTENT)
    out["init_rc"] = fd
    out["init_errno"] = ename
    if fd < 0:
        # EINVAL here is the kernel's own answer: permission events are compiled
        # out. That is a clean no and must not be confused with a bad call.
        out["verdict"] = "NO_PERM_CLASS"
        emit(out)
        return 0

    ok, e, ename = fan_mark(fd, FAN_MARK_ADD, FAN_OPEN_PERM | FAN_EVENT_ON_CHILD, marked)
    out["mark_ok"] = ok
    out["mark_errno"] = ename
    if not ok:
        out["verdict"] = "MARK_REFUSED"
        os.close(fd)
        emit(out)
        return 0

    allow_file = os.path.join(marked, "allow.txt")
    deny_file = os.path.join(marked, "deny.txt")
    free_file = os.path.join(unmarked, "free.txt")

    pid = os.fork()
    if pid == 0:
        # Child: the opener, as uid 1000. It must not hold the group fd.
        os.close(fd)
        res = {}
        try:
            os.setgid(1000)
            os.setuid(1000)
            res["uid"] = os.getuid()
        except OSError as ex:
            res["setuid_error"] = str(ex)
        for label, path in (("allow", allow_file), ("deny", deny_file), ("free", free_file)):
            t0 = time.time()
            try:
                h = os.open(path, os.O_WRONLY)
                os.close(h)
                res[label] = {"ok": True, "errno": None, "elapsed": round(time.time() - t0, 3)}
            except OSError as ex:
                res[label] = {
                    "ok": False,
                    "errno": errno.errorcode.get(ex.errno, str(ex.errno)),
                    "elapsed": round(time.time() - t0, 3),
                }
        with open("/var/tmp/g4/client.json", "w") as fh:
            json.dump(res, fh)
        os._exit(0)

    # Parent: the daemon.
    log = []
    deadline = time.time() + 45
    seen_allow = seen_deny = False
    while time.time() < deadline:
        ev = read_event(fd, 2.0)
        if ev is None:
            if seen_allow and seen_deny:
                break
            continue
        mask, evfd, epid, vers = ev
        path = fd_path(evfd)
        base = os.path.basename(path)
        if base == "deny.txt":
            n = respond(fd, evfd, FAN_DENY)
            seen_deny = True
            log.append({"path": path, "pid": epid, "verdict": "DENY", "response_bytes": n,
                        "delayed": 0.0, "abi_version": vers})
        else:
            time.sleep(delay)
            n = respond(fd, evfd, FAN_ALLOW)
            if base == "allow.txt":
                seen_allow = True
            log.append({"path": path, "pid": epid, "verdict": "ALLOW", "response_bytes": n,
                        "delayed": delay, "abi_version": vers})
        os.close(evfd)

    os.waitpid(pid, 0)
    os.close(fd)

    out["daemon_log"] = log
    try:
        with open("/var/tmp/g4/client.json") as fh:
            out["client"] = json.load(fh)
    except (OSError, ValueError) as ex:
        out["client_error"] = str(ex)

    c = out.get("client", {})
    a = c.get("allow", {})
    d = c.get("deny", {})
    f = c.get("free", {})
    deny_issued = any(x["verdict"] == "DENY" and x["response_bytes"] == 8 for x in log)
    out["evidence"] = {
        "allow_blocked": bool(a.get("ok")) and a.get("elapsed", 0) >= (delay * 0.8),
        "allow_elapsed": a.get("elapsed"),
        "deny_refused": (d.get("ok") is False) and d.get("errno") == "EPERM",
        "deny_errno": d.get("errno"),
        "deny_was_issued": deny_issued,
        "unmarked_opened_normally": bool(f.get("ok")) and f.get("elapsed", 99) < (delay * 0.5),
        "unmarked_elapsed": f.get("elapsed"),
        "events_delivered": len(log),
    }
    ev = out["evidence"]
    if ev["allow_blocked"] and ev["deny_refused"] and ev["deny_was_issued"] and ev["unmarked_opened_normally"]:
        out["verdict"] = "ENFORCED"
    elif len(log) == 0:
        out["verdict"] = "NO_EVENTS"
    elif not ev["allow_blocked"]:
        out["verdict"] = "NOTIFICATION_ONLY"
    elif not ev["deny_refused"]:
        out["verdict"] = "DENY_IGNORED"
    else:
        out["verdict"] = "PARTIAL"
    emit(out)
    return 0


# --------------------------------------------------------------- scope ------
def cmd_scope(path):
    """Question 2. Which mark SCOPES does this kernel accept on this path?

    A fresh group per scope, because a group that already holds a mark can
    succeed for the wrong reason.
    """
    out = {"cmd": "scope", "path": path, "scopes": {}}
    for name, flags in (
        ("directory", FAN_MARK_ADD),
        ("directory_with_children", FAN_MARK_ADD),
        ("mount", FAN_MARK_ADD | FAN_MARK_MOUNT),
        ("filesystem", FAN_MARK_ADD | FAN_MARK_FILESYSTEM),
    ):
        fd, e, ename = fan_init(FAN_CLOEXEC | FAN_CLASS_CONTENT)
        if fd < 0:
            out["scopes"][name] = {"ok": False, "errno": ename, "note": "group could not be created"}
            continue
        mask = FAN_OPEN_PERM
        if name == "directory_with_children":
            mask |= FAN_EVENT_ON_CHILD
        ok, e, ename = fan_mark(fd, flags, mask, path)
        out["scopes"][name] = {"ok": ok, "errno": ename}
        os.close(fd)
    emit(out)
    return 0


# --------------------------------------------------------------- count ------
def cmd_count(path, seconds, outfile, ignore_dir=None):
    """Question 3. Notification mode only. Nothing is blocked and nothing is at
    risk. Counts write-ish events and buckets them by path prefix.

    With ignore_dir set, this also answers the follow-up that decides viability:
    an FAN_MARK_IGNORED_MASK placed on a subtree is an exclusion applied AT MARK
    PLACEMENT TIME. If events from inside it stop being delivered while events
    outside continue, the kernel is doing the filtering and the cost is not paid.
    """
    out = {"cmd": "count", "path": path, "seconds": seconds, "ignore_dir": ignore_dir}
    fd, e, ename = fan_init(FAN_CLOEXEC | FAN_NONBLOCK | FAN_CLASS_NOTIF)
    out["init_errno"] = ename
    if fd < 0:
        out["verdict"] = "INIT_FAILED"
        emit(out)
        return 0

    mask = FAN_MODIFY | FAN_CLOSE_WRITE
    ok, e, ename = fan_mark(fd, FAN_MARK_ADD | FAN_MARK_MOUNT, mask, path)
    out["mount_mark_ok"] = ok
    out["mount_mark_errno"] = ename
    if not ok:
        ok, e, ename = fan_mark(fd, FAN_MARK_ADD | FAN_EVENT_ON_CHILD, mask, path)
        out["dir_mark_ok"] = ok
        out["dir_mark_errno"] = ename
        if not ok:
            out["verdict"] = "MARK_REFUSED"
            os.close(fd)
            emit(out)
            return 0

    if ignore_dir:
        ok, e, ename = fan_mark(
            fd,
            FAN_MARK_ADD | FAN_MARK_IGNORED_MASK | FAN_MARK_IGNORED_SURV_MODIFY,
            mask,
            ignore_dir,
        )
        out["ignore_mark_ok"] = ok
        out["ignore_mark_errno"] = ename

    buckets = {".git": 0, "node_modules": 0, "__pycache__": 0, ".venv": 0,
               "build_output": 0, "ignored_subtree": 0, "other": 0}
    total = 0
    samples = []
    deadline = time.time() + seconds
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 1.0)
        if not r:
            continue
        try:
            buf = os.read(fd, METADATA_LEN * 256)
        except OSError:
            continue
        off = 0
        while off + METADATA_LEN <= len(buf):
            event_len, vers, _res, _mlen, m, evfd, epid = struct.unpack(
                "=IBBHQii", buf[off:off + METADATA_LEN])
            if event_len <= 0:
                break
            if evfd >= 0:
                p = fd_path(evfd)
                os.close(evfd)
                total += 1
                if len(samples) < 40:
                    samples.append(p)
                if ignore_dir and p.startswith(ignore_dir):
                    buckets["ignored_subtree"] += 1
                elif "/.git/" in p or p.endswith("/.git"):
                    buckets[".git"] += 1
                elif "/node_modules/" in p:
                    buckets["node_modules"] += 1
                elif "/__pycache__/" in p:
                    buckets["__pycache__"] += 1
                elif "/.venv/" in p:
                    buckets[".venv"] += 1
                elif "/dist/" in p or "/build/" in p or "/out/" in p or "/target/" in p:
                    buckets["build_output"] += 1
                else:
                    buckets["other"] += 1
            off += event_len
    os.close(fd)
    out["total"] = total
    out["buckets"] = buckets
    out["samples"] = samples
    excluded = buckets[".git"] + buckets["node_modules"] + buckets["__pycache__"] + \
        buckets[".venv"] + buckets["build_output"]
    out["excluded_prefix_count"] = excluded
    out["excluded_prefix_pct"] = round(100.0 * excluded / total, 1) if total else 0.0
    with open(outfile, "w") as fh:
        json.dump(out, fh)
    emit(out)
    return 0


# ------------------------------------------------------------ allowall ------
def cmd_daemon(path, seconds, snapdir=None):
    """Question 5, runs B and C. Permission mode over a whole mount, allowing
    everything. With snapdir set, the file is copied before the allow, which is
    the snapshot cost.

    THE RE-ENTRANCY HAZARD, AND WHY THE OBVIOUS COPY IS FATAL.

    The daemon never writes inside `path`: the snapshot lands on ext4 under
    /var/tmp. That is necessary and it is NOT sufficient, which cost a run.

    The first version copied with open("/proc/self/fd/%d" % evfd). That is a
    fresh open() ON THE MARKED MOUNT, so it generates another FAN_OPEN_PERM
    event, and the daemon is already inside the copy and single threaded, so it
    can never answer it. The daemon deadlocks against itself, and because the
    mark is mount-scoped, EVERY open on the granted workspace blocks behind it.
    On the box that wedged the on-VM job runner and silently killed the rest of
    the run: the driver polled a dead runner for 27 minutes.

    os.dup() duplicates the descriptor the kernel already handed us. It is not an
    open, it generates no event, and it cannot re-enter. Any future work here
    must preserve that property: inside the event loop, never open a path.
    """
    out = {"cmd": "daemon", "path": path, "seconds": seconds, "snapdir": snapdir}
    fd, e, ename = fan_init(FAN_CLOEXEC | FAN_CLASS_CONTENT)
    out["init_errno"] = ename
    if fd < 0:
        out["verdict"] = "INIT_FAILED"
        emit(out)
        return 0
    ok, e, ename = fan_mark(fd, FAN_MARK_ADD | FAN_MARK_MOUNT, FAN_OPEN_PERM, path)
    out["mark_ok"] = ok
    out["mark_errno"] = ename
    if not ok:
        out["verdict"] = "MARK_REFUSED"
        os.close(fd)
        emit(out)
        return 0
    if snapdir:
        os.makedirs(snapdir, exist_ok=True)

    handled = 0
    copied = 0
    copy_seconds = 0.0
    deadline = time.time() + seconds
    while time.time() < deadline:
        ev = read_event(fd, 1.0)
        if ev is None:
            continue
        mask, evfd, epid, vers = ev
        # Never adjudicate our own opens. Belt and braces beside the dup below:
        # if anything in this loop ever does open a path, this stops it wedging
        # the whole mount rather than merely being slow.
        if epid == os.getpid():
            respond(fd, evfd, FAN_ALLOW)
            os.close(evfd)
            continue
        if snapdir:
            t0 = time.time()
            try:
                dest = os.path.join(snapdir, "snap-%d" % handled)
                # os.dup, NOT open("/proc/self/fd/N"). See the docstring: the
                # latter is an open on the marked mount and deadlocks the daemon
                # against itself.
                dup = os.dup(evfd)
                try:
                    os.lseek(dup, 0, os.SEEK_SET)
                    with open(dest, "wb") as dst:
                        while True:
                            chunk = os.read(dup, 65536)
                            if not chunk:
                                break
                            dst.write(chunk)
                finally:
                    os.close(dup)
                copied += 1
            except (OSError, IOError):
                pass
            copy_seconds += time.time() - t0
        respond(fd, evfd, FAN_ALLOW)
        os.close(evfd)
        handled += 1
    os.close(fd)
    out["handled"] = handled
    out["copied"] = copied
    out["copy_seconds"] = round(copy_seconds, 3)
    emit(out)
    return 0


# ---------------------------------------------------------------- hold ------
def cmd_hold(path, delay, seconds, pidfile):
    """Question 2. A long-lived holder of a permission mark, so survival across
    the WSL restart cycle and a reboot can be tested FUNCTIONALLY.

    'The unit is active' is not the claim. A unit can be active while its mark is
    gone, which is exactly the failure a survival test exists to catch. So this
    holds a real FAN_OPEN_PERM mark and delays every allow by `delay`, which lets
    the tester prove the mark is live by timing an open from uid 1000 rather than
    by asking systemd how it feels.
    """
    fd, e, ename = fan_init(FAN_CLOEXEC | FAN_CLASS_CONTENT)
    if fd < 0:
        emit({"cmd": "hold", "init_errno": ename, "verdict": "INIT_FAILED"})
        return 1
    ok, e, ename = fan_mark(fd, FAN_MARK_ADD, FAN_OPEN_PERM | FAN_EVENT_ON_CHILD, path)
    if not ok:
        emit({"cmd": "hold", "mark_errno": ename, "verdict": "MARK_REFUSED"})
        os.close(fd)
        return 1
    with open(pidfile, "w") as fh:
        fh.write(json.dumps({"pid": os.getpid(), "path": path, "delay": delay,
                             "started": time.time()}))
    emit({"cmd": "hold", "pid": os.getpid(), "path": path, "delay": delay,
          "seconds": seconds, "verdict": "HOLDING"})
    deadline = time.time() + seconds
    while time.time() < deadline:
        ev = read_event(fd, 1.0)
        if ev is None:
            continue
        mask, evfd, epid, vers = ev
        time.sleep(delay)
        respond(fd, evfd, FAN_ALLOW)
        os.close(evfd)
    os.close(fd)
    return 0


def main():
    if len(sys.argv) < 2:
        emit({"error": "no subcommand"})
        return 2
    c = sys.argv[1]
    if c == "hold":
        return cmd_hold(sys.argv[2], float(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
    if c == "perm":
        return cmd_perm(sys.argv[2], sys.argv[3], float(sys.argv[4]))
    if c == "scope":
        return cmd_scope(sys.argv[2])
    if c == "count":
        ign = sys.argv[5] if len(sys.argv) > 5 else None
        return cmd_count(sys.argv[2], int(sys.argv[3]), sys.argv[4], ign)
    if c == "daemon":
        snap = sys.argv[4] if len(sys.argv) > 4 else None
        return cmd_daemon(sys.argv[2], int(sys.argv[3]), snap)
    if c == "selftest":
        # Proves the interpreter can reach libc and that the constant table is
        # loaded, WITHOUT asserting anything about the kernel. A phase that
        # cannot tell "python is broken" from "the kernel said no" is not
        # measuring the kernel.
        fd, e, ename = fan_init(FAN_CLOEXEC | FAN_CLASS_NOTIF)
        ok = fd >= 0
        if ok:
            os.close(fd)
        emit({"cmd": "selftest", "python": sys.version.split()[0],
              "libc_reachable": True, "notif_group_ok": ok, "notif_errno": ename})
        return 0
    emit({"error": "unknown subcommand", "arg": c})
    return 2


if __name__ == "__main__":
    sys.exit(main())
'@

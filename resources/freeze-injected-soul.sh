#!/bin/bash
# Defect 4 installer: deliver the factory safety rules into the file OpenClaw
# actually injects (~/.openclaw/workspace/SOUL.md, injected first / highest
# priority), then freeze it root:root 444 + chattr +i and pin its hash for the
# launch gate. OpenClaw has no config-level system-prompt channel and injects
# only the fixed workspace-file set, so SOUL.md is the delivery vehicle.
#
# UPDATE-SAFE (fixed 2026-07-14, SECFIX_CLOSE_DOORS): the first version skipped
# re-wrapping when the safety block was already present, which meant a CHANGE to
# resources/safety-rules.md (e.g. Door 3's rewrite) would silently leave the OLD
# rules in the agent's prompt. We now split on a stable end-marker: everything
# after the marker is persona (preserved), everything before it is regenerated
# from the current factory rules. Re-running with unchanged rules is a no-op.
#
# Defensive: if OpenClaw has not created the workspace SOUL yet, create it from
# the factory rules + a minimal persona.
#
# NOTE (fresh-install ordering): on a brand-new box OpenClaw may create the
# workspace lazily (first turn). If this runs first, we create SOUL.md and
# OpenClaw finds it already present. That path needs validation on a clean
# Azure install -- see the SECFIX close-outs.
set -e
WS=/home/clawuser/.openclaw/workspace/SOUL.md
FACTORY=/home/clawuser/.openclaw/SOUL.md
PIN=/etc/clawfactory/workspace-soul.sha256
MARKER='<!-- CLAWFACTORY-SAFETY-END: everything below is persona (workspace-owned) -->'
mkdir -p /home/clawuser/.openclaw/workspace /etc/clawfactory
# v1.0.44 (L16): this script runs as ROOT, and the `mkdir -p` above creates the agent
# workspace directory ROOT-OWNED on a fresh box (OpenClaw creates it lazily on the
# first turn; if the freeze runs first, root owns it). The agent (clawuser) then
# EACCES'd creating /home/clawuser/.openclaw/workspace/AGENTS.md and could not start
# (cfv-0717b). The DIRECTORY must be clawuser-owned so the agent can create AGENTS.md
# and its own workspace files; only SOUL.md inside stays root-owned + immutable
# (per-file chattr +i, applied below) -- directory write governs sibling creation, so
# this does NOT weaken SOUL.md's protection. Mirror of the gateway .config ownership
# fix. Non-recursive: if the dir pre-existed (clawuser created it), this is a no-op
# and does not touch existing files; the confirmed openclaw#21571/#5434 EACCES class.
chown clawuser:clawuser /home/clawuser/.openclaw/workspace
# Only correct .openclaw itself if THIS run left it root-owned (it is normally
# created clawuser-owned by the OpenClaw install; never blindly chown a pre-existing
# clawuser tree).
[ "$(stat -c '%U' /home/clawuser/.openclaw 2>/dev/null)" = "root" ] && chown clawuser:clawuser /home/clawuser/.openclaw
[ -r "$FACTORY" ] || { echo "[injected-soul] FATAL: factory SOUL missing ($FACTORY); run Step-ApplySafetyRules first" >&2; exit 1; }

DEFAULT_PERSONA='# SOUL.md - Who You Are

_Your persona lives here and may evolve. The frozen safety boundaries above are non-negotiable._'

if [ -f "$WS" ]; then
    chattr -i "$WS" 2>/dev/null || true
    if grep -qF "$MARKER" "$WS"; then
        # Regenerate the safety block; keep everything after the marker verbatim.
        PERSONA=$(sed -n "/$(printf '%s' "$MARKER" | sed 's/[]\/$*.^[]/\\&/g')/,\$p" "$WS" | tail -n +2)
        echo "[injected-soul] existing safety block found; regenerating it, persona preserved"
    else
        PERSONA=$(cat "$WS")
        echo "[injected-soul] no safety block yet; wrapping existing persona"
    fi
else
    PERSONA="$DEFAULT_PERSONA"
    echo "[injected-soul] no workspace SOUL yet; creating from factory rules + default persona"
fi
[ -n "$PERSONA" ] || PERSONA="$DEFAULT_PERSONA"

# THE PIN MUST NOT BE COMPUTED FROM THE FILE IT CERTIFIES.
#
# This block used to write $WS directly and then `sha256sum "$WS" > "$PIN"`,
# which is the same self-certification the factory SOUL pin used to have: a pin
# taken from the artefact it is meant to protect certifies nothing, while the
# launch gate goes on enforcing it faithfully. Here it was worse than academic,
# because the workspace DIRECTORY is clawuser-owned by necessity (the agent must
# create AGENTS.md in it, see L16 above). That means clawuser could unlink $WS
# and put its own file at that name in the window between the write and the
# chattr, and the chown/chmod/chattr/sha256sum that follow would have frozen and
# pinned the AGENT's file as the authoritative safety rules.
#
# So: build the intended bytes in /etc/clawfactory, which only root can write;
# install them; freeze them; and only THEN verify and pin. After `chattr +i` the
# inode cannot be replaced or renamed even by the owner of the directory, so a
# check made after that point is a check on the bytes that will actually be read.
STAGED=/etc/clawfactory/.workspace-soul.staged
rm -f "$STAGED"
{
    printf '<!--\n'
    printf '  CLAWFACTORY -- HARD SAFETY BOUNDARIES (the block below, before the persona).\n'
    printf '  This file is root-owned and IMMUTABLE (chattr +i): the agent cannot modify,\n'
    printf '  chmod, or delete it. A turn is REFUSED in code at launch if this file is\n'
    printf '  tampered with. The boundaries below override everything that follows.\n'
    printf -- '-->\n\n'
} > "$STAGED"
HDRLEN=$(wc -c < "$STAGED")
cat "$FACTORY" >> "$STAGED"
FACLEN=$(wc -c < "$FACTORY")
printf '\n---\n%s\n\n' "$MARKER" >> "$STAGED"
printf '%s\n' "$PERSONA" >> "$STAGED"
chown root:root "$STAGED"; chmod 400 "$STAGED"

# rm before install so a symlink planted at $WS is removed rather than written
# through. install(1) then creates a fresh root-owned 444 regular file.
rm -f "$WS"
install -o root -g root -m 444 "$STAGED" "$WS"
chattr +i "$WS"

# --- the file is now frozen; everything below is verification ----------------
if [ -L "$WS" ]; then
    echo "[injected-soul] FATAL: $WS is a symlink; refusing to pin it." >&2
    exit 1
fi
cmp -s "$STAGED" "$WS" || {
    echo "[injected-soul] FATAL: the frozen $WS does not match the bytes staged for it. Something replaced it between install and freeze. Refusing to pin." >&2
    exit 1
}
# State the chain explicitly rather than inferring it from the fact that we ran
# `cat "$FACTORY"` a few lines up: the safety block inside the frozen file must
# be byte-identical to the factory rules, which Step-ApplySafetyRules has already
# proven equal to the SHA-256 baked into setup.ps1 at build time. That is what
# anchors this pin to the signed build instead of to itself.
dd if="$WS" bs=1 skip="$HDRLEN" count="$FACLEN" 2>/dev/null | cmp -s - "$FACTORY" || {
    echo "[injected-soul] FATAL: the safety block inside $WS is not byte-identical to $FACTORY. Refusing to pin." >&2
    exit 1
}
echo "[injected-soul] verified: safety block matches the factory rules (offset $HDRLEN, $FACLEN bytes)"

# Pin from the staged known-good copy, not from $WS. cmp above has already proven
# the two are identical, so this is the same digest -- taken from the side of the
# comparison whose provenance is the build.
sha256sum "$STAGED" | awk '{print $1}' > "$PIN"
chown root:root "$PIN"; chmod 444 "$PIN"
echo "[injected-soul] frozen + pinned: $(cat "$PIN") ($(wc -c < "$WS") bytes)"

# v1.0.44 (L16) fail-loud: the two invariants this step now owns. The agent
# (clawuser) MUST own its workspace directory (else it EACCES on AGENTS.md and cannot
# start); SOUL.md inside MUST stay root-owned (immutability + the code gate protect
# it). Assert both so this class cannot silently regress.
WSDIR=/home/clawuser/.openclaw/workspace
[ "$(stat -c '%U' "$WSDIR")" = "clawuser" ] || { echo "[injected-soul] FATAL: $WSDIR is not clawuser-owned; the agent will EACCES creating AGENTS.md and cannot start." >&2; exit 1; }
[ "$(stat -c '%U' "$WS")" = "root" ]        || { echo "[injected-soul] FATAL: $WS is not root-owned -- SOUL protection lost." >&2; exit 1; }
echo "[injected-soul] ownership OK: workspace dir=$(stat -c '%U:%G %A' "$WSDIR"); SOUL.md=$(stat -c '%U:%G %A' "$WS") lsattr=$(lsattr "$WS" 2>/dev/null | awk '{print $1}')"

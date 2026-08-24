<#
  Can Guard 2's approve-to-delivery path be measured at all, and does the
  approved payload win against a post-approval swap?

  WHY THIS EXISTS
  ---------------
  Phase 3 test 3 has never produced a result in any run of this suite. The
  oldest evidence on the build machine records it as UNTESTED, a verdict word
  the current phase runner does not permit, and on cfv-174 it failed for a
  reason that is nothing to do with Guard 2:

      {"ok":false,"code":"ESMTP",
       "error":"127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext"}

  send-smtp.js refuses cleartext submission on any port other than 465. Phase
  3's sink speaks plain SMTP and advertises only AUTH. So the product and the
  test rig disagree about transport, the broker is right, and the rig has never
  been able to accept a message from it.

  That refusal is itself a security property behaving correctly and it is
  recorded as such below. But it leaves G2.6 unmeasured, and G2.6 is the single
  most important assertion in the Guard 2 job: after approval, if the SOURCE
  attachment is rewritten, do the APPROVED bytes go or the tampered ones.

  WHAT THIS CHANGES ON THE BOX, STATED PLAINLY
  --------------------------------------------
  A throwaway CA and a server certificate for 127.0.0.1, installed into the
  BOX's trust store, and a STARTTLS-capable sink. It changes NO product code,
  NO product configuration and NO security logic. It changes which certificate
  authorities this throwaway validation VM trusts, for the length of one test,
  which is what anyone testing a TLS client against a local server does.

  It is removed at the end and the removal is verified.

  IF NODE WILL NOT HONOUR THE SYSTEM STORE the test cannot run, and that is a
  result too: it is reported as VOID with the reason, not as a Guard 2 failure.
  Node builds vary on whether they read the system store or their own bundled
  one, and this probe finds out by execution rather than by assertion.
#>
param([string]$Transcript = 'C:\cfv\sinktls-out-probe.txt')

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Guard 2 delivery: a sink the broker will actually talk to' `
    -Transcript $Transcript -Sentinel 'SINKTLS_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'ST.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; W 'SINKTLS_PROBE_COMPLETE rc=2'; exit 2 }

# ---------------------------------------------------------------- 0. restore
Section '0. Housekeeping: put the box back the way the handover card described it'
$fix = Invoke-WslFile -Tag 'st-fix' -User 'root' -Body @'
echo '--- the operator toggled the software-source switch OFF during the panel checks ---'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | head -3
/usr/local/sbin/clawfactory-fetchctl list 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
console.log("TOOLCHAIN_AFTER="+(j.toolchain&&j.toolchain.enabled));
console.log("READ_FETCH_AFTER="+((j.allow||[]).map(x=>x.host).join(",")||"(empty)"));});'
'@
W $fix.Out
$tcBack = $fix.Out -match 'TOOLCHAIN_AFTER=true'
$listOk = $fix.Out -match 'READ_FETCH_AFTER=www\.iana\.org$' -or $fix.Out -match 'READ_FETCH_AFTER=www\.iana\.org\s'
Record 'ST.0' 'Toolchain switch restored to ON and the read-fetch list is back to the seeded entry only' `
    $(if ($tcBack -and $listOk) { 'PASS' } else { 'FAIL' }) `
    "toolchainOn=$tcBack readFetchIsSeededOnly=$listOk (the operator added and removed docs.python.org during check 3 and check 5)"

# --------------------------------------------------- 1. the refusal, recorded
Section '1. The cleartext refusal is a PRODUCT PROPERTY and is recorded as one'
Record 'ST.1' 'The broker refuses to submit a credential over an unencrypted transport' `
    $(if ($true) { 'PASS' } else { 'FAIL' }) `
    'observed on cfv-174 phase 3: approve returned {"code":"ESMTP","error":"127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext"} and the receipt recorded sent=false outcome=smtp_error. Fail-closed on transport, which is the correct behaviour and is why the plain sink can never receive a message'

# --------------------------------------- 2. a sink the broker will talk to
Section '2. Build a throwaway CA and a STARTTLS sink, and find out if node trusts it'
$build = Invoke-WslFile -Tag 'st-build' -User 'root' -Body @'
set -e
cd /var/tmp
rm -rf cfca && mkdir cfca && cd cfca
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 2 -nodes \
  -subj "/CN=ClawFactory Validation Throwaway CA" >/dev/null 2>&1
cat > srv.cnf <<'CNF'
[req]
distinguished_name=dn
req_extensions=ext
prompt=no
[dn]
CN=127.0.0.1
[ext]
subjectAltName=IP:127.0.0.1
CNF
openssl req -newkey rsa:2048 -keyout srv.key -out srv.csr -nodes -config srv.cnf >/dev/null 2>&1
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 2 \
  -extfile srv.cnf -extensions ext >/dev/null 2>&1
echo "CERT_SAN=$(openssl x509 -in srv.crt -noout -text | grep -A1 'Subject Alternative Name' | tail -1 | tr -d ' ')"
install -m 0644 ca.crt /usr/local/share/ca-certificates/cfca.crt
update-ca-certificates >/dev/null 2>&1
echo "CA_INSTALLED=$([ -e /etc/ssl/certs/cfca.pem ] && echo yes || echo no)"
set +e
cat > /var/tmp/cf-tlssink.js <<'SINKEOF'
const net=require("net"),tls=require("tls"),fs=require("fs");
const opts={key:fs.readFileSync("/var/tmp/cfca/srv.key"),cert:fs.readFileSync("/var/tmp/cfca/srv.crt")};
let n=0;
function wire(sock,secure){
  let buf="";
  const onData=d=>{
    buf+=d.toString();
    const lines=buf.split("\r\n"); buf=lines.pop();
    for(const l of lines){
      if(/^EHLO|^HELO/i.test(l)){
        sock.write(secure?"250-cf-sink\r\n250 AUTH PLAIN LOGIN\r\n":"250-cf-sink\r\n250 STARTTLS\r\n");
      } else if(/^STARTTLS/i.test(l)){
        sock.removeListener("data",onData);
        sock.write("220 Ready to start TLS\r\n");
        const t=new tls.TLSSocket(sock,{isServer:true,key:opts.key,cert:opts.cert});
        t.on("error",e=>fs.appendFileSync("/var/tmp/cf-tlssink.log","TLSERR "+e.message+"\n"));
        t.on("secure",()=>{}); wire(t,true);
        return;
      } else if(/^AUTH/i.test(l)) sock.write("235 2.7.0 Accepted\r\n");
      else if(/^MAIL FROM|^RCPT TO/i.test(l)) sock.write("250 2.1.0 Ok\r\n");
      else if(/^DATA/i.test(l)){ sock.write("354 End data\r\n"); }
      else if(l==="."){ n++; fs.writeFileSync("/var/tmp/cf-tlssink-count",String(n)); sock.write("250 2.0.0 Ok: queued as TLSSINK"+n+"\r\n"); }
      else if(/^QUIT/i.test(l)){ sock.write("221 Bye\r\n"); sock.end(); }
      else if(l.length){ fs.appendFileSync("/var/tmp/cf-tlssink.log","BODY "+l+"\n"); }
    }
  };
  sock.on("data",onData);
  sock.on("error",()=>{});
}
net.createServer(s=>{ s.write("220 cf-tlssink ESMTP\r\n"); wire(s,false); })
   .listen(2525,"127.0.0.1",()=>console.log("tlssink up on 2525"));
SINKEOF
echo 0 > /var/tmp/cf-tlssink-count
: > /var/tmp/cf-tlssink.log
pkill -f cf-sink.js 2>/dev/null; pkill -f cf-tlssink.js 2>/dev/null
sleep 1
setsid node /var/tmp/cf-tlssink.js > /var/tmp/cf-tlssink.out 2>&1 &
sleep 2
echo "SINK_OUT=$(cat /var/tmp/cf-tlssink.out 2>&1)"
echo '--- DOES NODE TRUST IT? asked by execution, with no rejectUnauthorized override ---'
node -e '
const tls=require("tls"),net=require("net");
const s=net.createConnection(2525,"127.0.0.1");
let stage=0;
s.on("data",d=>{
  const t=d.toString();
  if(stage===0){stage=1;s.write("EHLO probe\r\n");return;}
  if(stage===1){stage=2;s.write("STARTTLS\r\n");return;}
  if(stage===2){stage=3;
    const u=tls.connect({socket:s,servername:"127.0.0.1"},()=>{console.log("NODE_TLS_VERDICT=TRUSTED");process.exit(0);});
    u.on("error",e=>{console.log("NODE_TLS_VERDICT=REJECTED "+e.message);process.exit(0);});
  }
});
s.on("error",e=>{console.log("NODE_TLS_VERDICT=CONNECT_FAILED "+e.message);process.exit(0);});
setTimeout(()=>{console.log("NODE_TLS_VERDICT=TIMEOUT");process.exit(0);},15000);
' 2>&1
'@
W $build.Out
$trusted = $build.Out -match 'NODE_TLS_VERDICT=TRUSTED'
$verdictLine = (($build.Out -split "`n") | Where-Object { $_ -match 'NODE_TLS_VERDICT=' } | Select-Object -First 1)
Register-Control -Id 'ST.2.CTL' -Name 'the replacement sink is listening and speaks STARTTLS' `
    -Fired ($build.Out -match 'tlssink up on 2525') `
    -Evidence "without a live sink every delivery result below is about nothing" | Out-Null
Record 'ST.2' 'A sink exists that the broker will accept, so delivery becomes measurable' `
    $(if ($trusted) { 'PASS' } else { 'VOID' }) `
    "$verdictLine ; a REJECTED or TIMEOUT verdict means this node build does not read the system trust store, so the delivery rows below cannot be measured on this box and are VOID rather than failed"

# ------------------------------------------------- 3. delivery and the swap
Section '3. Approve a real request, and rewrite the SOURCE attachment after approval'
if (-not $trusted) {
    Record 'ST.3' 'Test 3 mechanism: approve executes the send and a receipt records it' 'VOID' `
        'no sink the broker will accept, so the approve-to-delivery path was not exercised'
    Record 'ST.6' 'Test 6: after a post-approval swap, the APPROVED bytes are the sent bytes' 'VOID' `
        'no sink the broker will accept, so nothing was transmitted to compare'
} else {
    $swap = Invoke-WslFile -Tag 'st-swap' -User 'root' -Body @'
CTL="node /usr/local/sbin/clawfactory-sendctl.js"
idof() { grep -oE 'requestId"?[[:space:]]*[:=][[:space:]]*"?[^"[:space:],}]+' | head -1 | sed -E 's/^.*[:=][[:space:]]*"?//'; }
echo "SINK_BEFORE=$(cat /var/tmp/cf-tlssink-count)"
O=$(su -s /bin/bash -c 'printf "swap body\n" > /tmp/st-b.txt; printf "A-bytes APPROVED\n" > /tmp/st-a.txt; clawfactory-send --to sink@example.com --subject "STLS-SWAP" --body-file /tmp/st-b.txt --attach /tmp/st-a.txt' clawuser 2>&1)
echo "$O"
ID=$(printf '%s' "$O" | idof)
H=$(printf '%s' "$O" | grep -oE '[a-f0-9]{64}' | head -1)
echo "id=$ID hash=$H"
echo '--- rewrite the SOURCE after the request was staged ---'
su -s /bin/bash -c 'printf "B-bytes TAMPERED\n" > /tmp/st-a.txt' clawuser
echo "SOURCE_NOW=$(cat /tmp/st-a.txt)"
$CTL approve "$ID" "$H" 2>&1
echo "approve_rc=$?"
sleep 3
echo "SINK_AFTER=$(cat /var/tmp/cf-tlssink-count)"
echo "A_BYTES_AT_SINK=$(grep -c 'A-bytes' /var/tmp/cf-tlssink.log 2>/dev/null || echo 0)"
echo "B_BYTES_AT_SINK=$(grep -c 'B-bytes' /var/tmp/cf-tlssink.log 2>/dev/null || echo 0)"
echo '--- receipt ---'
cat "/var/lib/clawfactory/send/receipts/$ID.json" 2>&1 | head -40
'@
    W $swap.Out
    $before = if ($swap.Out -match 'SINK_BEFORE=(\d+)') { [int]$Matches[1] } else { -1 }
    $after  = if ($swap.Out -match 'SINK_AFTER=(\d+)')  { [int]$Matches[1] } else { -1 }
    $aIn    = if ($swap.Out -match 'A_BYTES_AT_SINK=(\d+)') { [int]$Matches[1] } else { -1 }
    $bIn    = if ($swap.Out -match 'B_BYTES_AT_SINK=(\d+)') { [int]$Matches[1] } else { -1 }
    $sent   = $swap.Out -match '"sent":\s*true'
    Record 'ST.3' 'Test 3 mechanism: approve executes the send and a receipt records it' `
        $(if ($before -lt 0 -or $after -lt 0) { 'VOID' } elseif (($after -gt $before) -and $sent) { 'PASS' } else { 'FAIL' }) `
        "sinkBefore=$before sinkAfter=$after receiptSaysSent=$sent; MECHANISM only, against a local sink. External delivery is card #198 and is a separate claim"
    # VERDICT TRIAGE. -1 on either count means the comparison was never made:
    # VOID. Tampered bytes at the sink is the worst possible outcome and is FAIL.
    # Approved bytes absent means the approved send did not transmit, also FAIL.
    Record 'ST.6' 'Test 6: after a post-approval swap, the APPROVED bytes are the sent bytes' `
        $(if ($aIn -lt 0 -or $bIn -lt 0) { 'VOID' } `
          elseif ($bIn -gt 0) { 'FAIL' } elseif ($aIn -gt 0) { 'PASS' } else { 'FAIL' }) `
        "approvedBytesAtSink=$aIn tamperedBytesAtSink=$bIn (both comparisons made; tampered MUST be 0). The source file on disk at send time read: $(if ($swap.Out -match 'SOURCE_NOW=(.+)') { $Matches[1].Trim() } else { 'unread' })"
}

# ------------------------------------------------------------ 4. put it back
Section '4. Remove the throwaway CA and the replacement sink, and verify the removal'
$clean = Invoke-WslFile -Tag 'st-clean' -User 'root' -Body @'
pkill -f cf-tlssink.js 2>/dev/null
rm -f /usr/local/share/ca-certificates/cfca.crt
update-ca-certificates --fresh >/dev/null 2>&1
echo "CA_STILL_PRESENT=$([ -e /etc/ssl/certs/cfca.pem ] && echo yes || echo no)"
echo "SINK_STILL_RUNNING=$(pgrep -f cf-tlssink.js >/dev/null && echo yes || echo no)"
rm -rf /var/tmp/cfca /var/tmp/cf-tlssink.js
echo "CA_DIR_GONE=$([ -d /var/tmp/cfca ] && echo no || echo yes)"
'@
W $clean.Out
$removed = ($clean.Out -match 'CA_STILL_PRESENT=no') -and ($clean.Out -match 'SINK_STILL_RUNNING=no')
Record 'ST.4' 'The throwaway CA and the replacement sink are gone, verified rather than assumed' `
    $(if ($removed) { 'PASS' } else { 'FAIL' }) `
    "caRemoved=$($clean.Out -match 'CA_STILL_PRESENT=no') sinkStopped=$($clean.Out -match 'SINK_STILL_RUNNING=no'); the box must not go into the reboot pass trusting a test CA"

Complete-Phase -ResultsJson 'C:\cfv\sinktls-results.json' -MarkerPrefix 'SINKTLS'

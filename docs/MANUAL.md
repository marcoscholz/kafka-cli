# kafka-cli

A thin bash wrapper around [kcat](https://github.com/edenhill/kcat) for reading and writing Kafka messages from the CLI.
It adds Unix `tail` semantics on top of kcat plus a few quality-of-life features:

## Features

- **`tail`-like reads** — `kafka-cli my-topic` prints up to the last 10 messages (total across all partitions) and exits. `kafka-cli -f my-topic` keeps following new messages, matching `tail -f`.
- **Human-readable `--since`** — say `"5 min ago"` or `"yesterday 09:00"` instead of a millisecond epoch.
- **SSH jump host via `--via`** — opens a SOCKS5 tunnel and runs kcat through
  `proxychains4`, so you can reach brokers that are only accessible from
  inside a remote network without running anything on the jump box.
- **Environment-variable configuration** — point the script at a default
  broker and jump host once, then invoke it with just a topic.

Default mode is **consume** (topic → stdout). Pass `--produce` to read stdin
and write one message per line to the topic. Read-side flags (`-n`, `-f`,
`--since`, `--from-beginning`) are silently ignored in produce mode.

## Prerequisites

| Tool           | Required for            | Install (Debian/Ubuntu)                       | Install (macOS)               |
| -------------- | ----------------------- | --------------------------------------------- | ----------------------------- |
| `kcat`         | everything              | `sudo apt install kcat`                       | `brew install kcat`           |
| `proxychains4` | `--via`                 | `sudo apt install proxychains4`               | `brew install proxychains-ng` (provides the `proxychains4` binary) |
| `ssh`          | `--via`                 | ships with every distro                       | ships with macOS              |
| GNU `date`     | human-readable `--since`| ships with every Linux distro                 | `brew install coreutils` (the script finds `gdate` automatically) |

The script detects missing binaries at startup and exits with a clear install
hint — you don't need to pre-check anything.

## Quickstart

```bash
# Last 10 messages total, then exit (classic `tail`)
./bin/kafka-cli my-topic

# Last 100 total, then exit
./bin/kafka-cli -n 100 my-topic

# Last 10 + follow new messages (classic `tail -f`)
./bin/kafka-cli -f my-topic

# Last 100 total + follow
./bin/kafka-cli -n 100 -f my-topic

# Time-based backfill, exit at the high-water mark
./bin/kafka-cli --since "5 min ago" my-topic

# Time-based backfill + follow, appended to a log file
./bin/kafka-cli --since "5 min ago" -f my-topic >> out.log

# Read from a different broker
./bin/kafka-cli --broker other.host:9092 my-topic

# Produce one message
echo '{"foo":1}' | ./bin/kafka-cli --produce my-topic

# Produce many messages (one per line)
./bin/kafka-cli --produce my-topic < payloads.jsonl
```

The produce-mode invocations are a bit verbose; the
[Environment variables and shell aliases](#environment-variables-and-shell-aliases)
section below shows how to get `ksend` as a short alias.

## Start position (consume mode): `-n`, `--since`, `--from-beginning`

Consume mode has three mutually-exclusive ways to pick where to start reading.
At most one may be given; if none is given, `-n 10` is used (matches Unix
`tail`).

| Flag                        | Start at                                                         |
| --------------------------- | ---------------------------------------------------------------- |
| `-n <count>` *(default 10)* | Up to `<count>` messages **total across all partitions**, from up to `<count>` offsets before the per-partition high-water mark |
| `--since <when>`            | First message with a timestamp ≥ the given moment                |
| `--from-beginning`          | Earliest offset still in the log (full retention-window replay)  |

`--from-beginning` is intended as a rarely-used escape hatch — on high-volume
topics it can replay a lot of data. Prefer `-n` or `--since` unless you
genuinely need the full history.

### `--since` time syntax

Anything GNU `date -d` understands:

- `"30 sec ago"`, `"1 min ago"`, `"2 hours ago"`
- `"yesterday 09:00"`
- `"2026-04-21 14:00 UTC"`

The resulting millisecond epoch is applied to **all partitions** — you don't
need to restrict to one partition to use a timestamp.

**Caveats:**

- The timestamp is matched against the per-message Kafka timestamp
  (`CreateTime` or `LogAppendTime` depending on topic config). Producer
  clock skew can shift the apparent start.
- If the requested time is older than the topic's retention window, you'll
  silently land at the earliest available offset rather than getting an
  error. Check retention with `kcat -b <broker> -L -t <topic> -J`.

## Exit behavior: `-f` / `--follow`

By default the script exits when every partition has been read up to its
high-water mark at the moment consumption started — Unix `tail` semantics.
Pass `-f` (or `--follow`) to keep following new messages after the initial
read:

```bash
kafka-cli -f my-topic                       # live stream, Ctrl-C to stop
kafka-cli --since "5 min ago" -f my-topic   # backfill + live stream
```

## `-J` / `--json` — emit kcat's JSON envelope

By default the script prints each message's payload, one per line. Pass `-J`
to emit kcat's full JSON envelope (`topic`, `partition`, `offset`,
`timestamp`, `key`, `payload`) instead:

```bash
kafka-cli -J my-topic | jq '{offset, ts: .timestamp, payload}'
```

Useful for debugging offset/timestamp issues or when you need the message key
alongside the payload. Note this **changes the output shape** — downstream
pipelines built around raw payloads will need to adapt.

## `--produce` — send messages from stdin

```bash
echo '{"symbol":"BTCUSD","qty":1.5}' | ./bin/kafka-cli --produce my-topic
./bin/kafka-cli --produce my-topic < payloads.jsonl
```

Each newline-delimited line of stdin is sent as one message. Read-side flags
(`-n`, `-f`, `--since`, `--from-beginning`) are silently ignored. Under the
hood this invokes `kcat -P -l` — see kcat(1) for key-delimiter, partition, and
timestamp-override flags if you need finer control.

## `--via` — tunnel through an SSH jump host

When the Kafka broker is only reachable from a remote network and you have
SSH access to a jump box (even one where you can't run any commands —
tunnel access is enough), use `--via`:

```bash
./bin/kafka-cli --via user@jump.example.com my-topic
```

### What the script does under the hood

1. Opens `ssh -N -D <local_port> user@jump.example.com` in the background.
   This creates a **SOCKS5 proxy** on `127.0.0.1:<local_port>` that forwards
   any TCP connection through the jump box — and, critically, also resolves
   DNS names on the remote side.
2. Writes a small `proxychains4` config file to `/tmp/…` pointing at that
   SOCKS port, with `proxy_dns` enabled.
3. Runs `proxychains4 -q -f <conf> kcat …`. `proxychains4` is an
   `LD_PRELOAD` library that intercepts `connect()` and `gethostbyname()`
   calls and reroutes them through the SOCKS proxy — kcat doesn't know
   anything changed.
4. On exit (normal, Ctrl-C, or error), a trap kills the SSH process and
   removes the temp config file.

This works for single-broker *and* multi-broker clusters: when kcat gets a
Kafka metadata response pointing at `kafka-broker-2.example.com:9092`, the
SOCKS proxy resolves that hostname on the jump box (where it's reachable)
and tunnels the connection.

### Configure SSH for a smoother experience

In `~/.ssh/config`, add a stanza for the jump host:

```sshconfig
Host kafka-jump
    HostName jump.example.com
    User your-username
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 3
    # Optional: keep a master connection alive so repeat invocations are instant.
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

Then:

```bash
./bin/kafka-cli --via kafka-jump my-topic
```

The `ControlMaster` / `ControlPersist` block means the first
`kafka-cli --via kafka-jump …` invocation establishes the SSH session,
and subsequent invocations reuse it — no re-authentication, tunnel comes
up in milliseconds.

### SOCKS port collisions

The default local SOCKS port is **10808**. If that's already in use,
SSH exits immediately with `bind [127.0.0.1]:10808: Address already in use`
and the script reports `SSH tunnel to … exited before the SOCKS port came
up`. Pick another port:

```bash
./bin/kafka-cli --via kafka-jump --socks-port 10810 my-topic
```

## Environment variables and shell aliases

All three relevant flags have env-var equivalents. When both are set, the
flag wins. Export the env vars and a couple of aliases in your shell profile
for a frictionless default:

```bash
# ~/.bashrc (or ~/.zshrc)

# Defaults for every invocation
export KAFKA_BROKER="broker.example.com:9092"
export KAFKA_CLI_VIA="kafka-jump"          # SSH Host alias from ~/.ssh/config
export KAFKA_CLI_SOCKS_PORT="10808"        # optional; default is 10808

# Shorter invocation names
alias ksend='kafka-cli --produce'
alias ktail='kafka-cli'
```

After `source ~/.bashrc` (or opening a new shell):

```bash
ktail my-topic                                  # last 10 + exit
ktail -n 100 my-topic                           # last 100 + exit
ktail -f my-topic                               # last 10 + follow
ktail --since "1 min ago" my-topic              # backfill + exit
ktail --broker other.host my-topic              # one-off broker override

echo '{"foo":1}' | ksend my-topic               # produce via the alias
ksend my-topic < payloads.jsonl
ktail --since "5 min ago" -f my-topic >> out.log  # backfill + follow, appended
```

> **Note on filesystem symlinks.** You could also create a `ksend`
> symlink pointing at `kafka-cli`, but the script currently doesn't switch
> modes based on `$0`, so the symlink wouldn't gain you anything over the
> alias above (you'd still need `--produce`). Aliases are the recommended
> path because they don't require any filesystem changes and don't interact
> badly with cross-platform sync tooling.

## Filtering

`kafka-cli` is deliberately "dumb" — in consume mode it prints every message
kcat delivers. Use the Unix pipeline for filtering:

```bash
# Substring filter (cheap, works on any text)
ktail my-topic | grep -F '"side":"buy"'

# JSON structural filter (needs jq)
ktail my-topic | jq -c 'select(.symbol=="BTCUSD" and .qty > 100)'

# Replay once, filter separately
ktail --from-beginning my-topic > /tmp/all.jsonl
jq -c 'select(.symbol=="BTCUSD")' /tmp/all.jsonl > btc.jsonl
jq -c 'select(.symbol=="ETHUSD")' /tmp/all.jsonl > eth.jsonl
```

## Troubleshooting

| Symptom                                                         | Likely cause / fix                                                                                         |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `kafka-cli: kcat not found on PATH`                            | Install kcat (`sudo apt install kcat`).                                                                    |
| `kafka-cli: proxychains4 required for --via`                   | Install proxychains4 (`sudo apt install proxychains4`).                                                    |
| `kafka-cli: cannot parse --since: …`                           | Your string isn't a `date -d` format. Try `"5 min ago"`, `"yesterday 09:00"`, or `"2026-04-21 14:00 UTC"`. |
| `SSH tunnel to … exited before the SOCKS port came up`          | SOCKS port collision (retry with `--socks-port N`), SSH auth failure, or jump host unreachable.            |
| Hangs after "Connected" but no messages                         | Local DNS leaking. Make sure the proxychains config has `proxy_dns` (the script writes this by default).   |
| `%3\|ERROR\|rdkafka#consumer-1\| [thrd:ssl://…]: …`             | kcat couldn't complete the handshake. Usually means the broker is reachable but requires auth — pass `-X` flags through a `$KCAT_CONFIG` file or extend the script. |
| Messages older than expected are missing                        | Topic retention has expired them. Check `kcat -b <broker> -L -t <topic>` for retention config.             |

## Related one-liners that don't need this script

If you don't need `--since` or `--via`, raw kcat is already tight:

```bash
# Tail from now
kcat -b <broker> -t <topic> -C -q

# Start from a specific millisecond epoch (what --since translates to)
kcat -b <broker> -t <topic> -C -q -o s@1777125600000

# Metadata inspection — partitions, leaders, retention-related config
kcat -b <broker> -L -t <topic> -J | jq '.topics[0]'

# Produce a single message
echo 'hello' | kcat -b <broker> -t <topic> -P
```

`kafka-cli` exists to save you from typing `$(date -d '5 min ago' +%s%3N)`
and from wiring up SOCKS proxies by hand.

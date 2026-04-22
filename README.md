# kafka-cli

A thin bash wrapper around [kcat](https://github.com/edenhill/kcat) for reading and writing Kafka messages from the CLI.
It adds Unix `tail` semantics on top of kcat plus a few quality-of-life features:

## Features
- **`tail`-like reads** — read the last N messages and exit, or `-f` to keep following, just like `tail -f`.
- **Human-readable `--since`** — `"5 min ago"`, `"yesterday 09:00"`, or any `date -d` string instead of a millisecond epoch.
- **SSH jump host via `--via`** — opens a SOCKS5 tunnel on the fly, no setup on the remote box.
- **Environment-variable configuration** — set broker and jump host once, then invoke with just a topic.
- **Simple send command** — `--produce` sends stdin to a topic, one message per line.

## Install
Install prerequisites:
````bash
# Debian/Ubuntu
sudo apt install kcat proxychains4

# macOS
brew install kcat proxychains-ng
````

Install the script to your bin folder:
````bash
KAFKA_CLI="https://raw.githubusercontent.com/marcoscholz/kafka-cli/v1.0.0/bin/kafka-cli"
mkdir -p ~/.local/bin
curl -fsSL "$KAFKA_CLI" -o ~/.local/bin/kafka-cli
chmod +x ~/.local/bin/kafka-cli
````

To always track the latest release, swap `v1.0.0` for `main` in the URL.
To verify the download, compare the SHA-256 against the value published on
the [Releases page](https://github.com/marcoscholz/kafka-cli/releases):
````bash
sha256sum ~/.local/bin/kafka-cli
````

Make sure `~/.local/bin` is on your `$PATH`. On most modern distros it's
added automatically once the directory exists; open a fresh shell after the
install. If it isn't picked up, add this to your `~/.bashrc` / `~/.zshrc`:
````bash
export PATH="$HOME/.local/bin:$PATH"
````

Set aliases in your `.bashrc`
````bash
# Defaults for every invocation
export KAFKA_BROKER="<my kafka server>"
# export KAFKA_CLI_VIA="kafka-jump"         # SSH Host alias from ~/.ssh/config
# export KAFKA_CLI_SOCKS_PORT="10808"       # optional; default is 10808

# Shorter invocation names
alias ksend='kafka-cli --produce'
alias ktail='kafka-cli'
````

## Examples
With `KAFKA_BROKER` exported and the aliases from above, most invocations fit on one line.

Read messages:
````bash
# Last 10 messages total, then exit — just like `tail`
ktail my-topic

# Last 100 total, then exit
ktail -n 100 my-topic

# Follow new messages — just like `tail -f`
ktail -f my-topic

# Backfill the last 5 minutes
ktail --since "5 min ago" my-topic

# Backfill from yesterday morning, then keep following
ktail --since "yesterday 09:00" -f my-topic
````

Send messages:
````bash
# One message
echo '{"hello":"world"}' | ksend my-topic

# Many messages, one per line
ksend my-topic < payloads.jsonl
````

One-off broker (without setting `KAFKA_BROKER`):
````bash
ktail --broker broker.example.com:9092 my-topic
````

Reach a broker that's only accessible from inside a remote network:
````bash
ktail --via user@jump.example.com my-topic
````

## Reference
- `kafka-cli --help` — full flag list with examples.
- [docs/MANUAL.md](docs/MANUAL.md) — detailed manual: start-position semantics, `--since` syntax, SSH/SOCKS walkthrough, troubleshooting.

## License
MIT — see [LICENSE](LICENSE).

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-22

### Added

- Initial release of `kafka-cli` — a thin bash wrapper around [kcat](https://github.com/edenhill/kcat) for reading and writing Kafka messages from the CLI.
- `tail`-like consume mode: last N messages total across partitions with `-n` (default 10), or keep streaming with `-f` / `--follow`.
- Human-readable `--since <when>` backfill accepting any GNU `date -d` string (e.g. `"5 min ago"`, `"yesterday 09:00"`, `"2026-04-21 14:00 UTC"`).
- `--from-beginning` full-retention replay as an escape hatch.
- `--produce` mode: read stdin and send one message per line.
- `--via <user@host>` SSH jump-host support via on-the-fly SOCKS5 tunnel + `proxychains4`, with automatic teardown on exit.
- Environment-variable defaults: `KAFKA_BROKER`, `KAFKA_CLI_VIA`, `KAFKA_CLI_SOCKS_PORT`. Empty / whitespace-only values are rejected; the broker must be set via env or `--broker`.
- `-J` / `--json` flag for kcat's JSON envelope output.
- `-V` / `--version` flag.
- Cross-platform `--since`: uses GNU `date` where available, falls back to `gdate` (coreutils) on macOS.
- Signal handling: `cleanup_tunnel` fires on `EXIT INT TERM HUP` so the SSH tunnel and proxychains config are torn down on Ctrl-C too.

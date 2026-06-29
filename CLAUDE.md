# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Bison Relay (BR) is a suite of programs for private, secure communication. The
server is oblivious to message contents (all messages are E2E encrypted), and
Lightning Network (Decred / `dcrlnd`) payments are required to send and receive
messages. The repo is a single Go module (`github.com/companyzero/bisonrelay`,
Go 1.23) plus a Flutter GUI.

## Common commands

```bash
# Full pre-commit check: tests + linters + proto lint (mirrors CI)
./goclean.sh

# Run the whole Go test suite
go test ./...

# Run a single package / test
go test ./client/... -run TestName -v
go test -count=1 ./session/

# Linters (config in .golangci.yml; build tags e2elegacylntest, dcrlnde2e)
golangci-lint run

# Build/run the CLI client and server
go install ./brclient && brclient   # first run launches a setup wizard
go install ./brserver && brserver
```

E2E client tests require a running server with LN payments (the dcrlnd
three-node tmux environment). They are gated behind build tags — see
`client/README.md`:

```bash
go run ./brserver -cfg client/e2e-legacy-ln-server.conf
go test -count=1 -run TestE2E -tags e2elegacylntest -v ./client/
```

### Flutter GUI (bruig)

The GUI embeds the Go client as a native library via cgo. `go generate` builds
the shared lib (`libgolib`), then `flutter build` packages it.

```bash
cd bruig
go generate ./golibbuilder            # desktop; add -tags android / -tags ios for mobile
cd flutterui/bruig
flutter build linux                   # or macos / windows / android / ios
```

### Regenerating generated code

- `clientrpc` Go bindings: `cd clientrpc && ./regen-clientrpc.sh` (requires
  `protoc`, `protolint`). CI fails if regen produces a dirty tree.
- The proto uses a custom generator, `internal/protoc-gen-go-svcintf`, which
  emits service-interface glue alongside the standard `protoc-gen-go` output.

### Versioning / releases

`scripts/bumpversion.sh <version>` updates the version string across
`brclient`, `brserver`, and the Flutter `pubspec.yaml` / Windows runner.
Version source of truth is `internal/version`.

## Architecture

The system has three cooperating roles: **clients** talk to each other only
through a relay **server**, which cannot read message contents. A separate
**RTDT** subsystem handles realtime (voice) chat.

### Client library (`client/`) — the core

`client/` is the heart of the project: a reusable Go library that both the CLI
(`brclient`) and the GUI (`bruig`, via `golib`) consume. Consumers build a
`Config`, create a `Client`, and call `Run()`, which blocks until a subsystem
fails or the context is canceled.

It is structured as layered, runnable state machines (each exposes a
synchronous, concurrent-safe API and does its work inside a `run()` loop). From
the network up (see the diagram in `client/README.md`):

- `net` — lower-level TLS connection.
- `connKeeper` — keeps a connection to the server alive; spawns a new
  `serverSession` per connection.
- `serverSession` — maintains the tag-stack invariant (max inflight non-acked
  messages) and per-session wire encryption.
- `rmq` — outbound RoutedMessage queue; **pays for each outbound RM via LN**
  before sending, and encrypts per RM type (cleartext / kx / ratchet).
- `rdzvManager` — inbound RM queue; manages rendezvous-point subscriptions and
  dispatches each pushed RM to the right `remoteUser`.
- `RemoteUser` — holds and advances the **double-ratchet** state for one peer;
  implements per-user operations (PMs, files, etc).

Feature areas are split across `client_*.go` files (kx, groupchat, posts,
content, payments, onboard, onchain, rtdt, …). Persistence is in
`client/clientdb`; shared interfaces in `client/clientintf`.

### Server (`server/`)

Accountless, anonymous relay. Clients use ephemeral identities and (over Tor)
hide their IP. The server tracks the minimum possible metadata, routing
messages between rendezvous points without being able to decrypt them.
Server-side storage is `server/serverdb`.

### Protocol (`rpc/`)

Defines the wire protocol and routed-message types shared by client and server.
C2S traffic is double-encrypted (TLS outer + NaCl secretbox inner); C2C adds a
third double-ratchet layer. Background docs live in `doc/` (C2S session,
payments, P2P KX, P2P messaging, RTDT).

### Cryptographic building blocks

- `ratchet/` — double ratchet implementation (with `ratchet/disk` persistence).
- `session/` — client↔server key exchange (sntrup4591761) and nonce sequencing.
- `zkidentity/` — identity / short-ID primitives.

### clientrpc (`clientrpc/`)

Automation API for driving a running `brclient` (bots, integrations). Disabled
by default; enabled via `[clientrpc] jsonrpclisten=...` in `brclient.conf`.
Authenticated with mutually-issued TLS client certs (generated into
`~/.brclient`). Service definitions are in `clientrpc.proto`; concrete types are
generated (see regen above). Example daemons are in `clientrpc/examples`.

### RTDT (`rtdt/`, `brrtdtserver/`)

Realtime chat / voice protocol with its own client and server. `internal/audio`
handles Opus encoding.

### Frontends

- `brclient/` — terminal UI built on Charm's bubbletea/bubbles/lipgloss.
  `appstate.go` wires the `client` library to the TUI.
- `bruig/` — Flutter GUI. `bruig/golib` exposes the Go client to Dart through a
  C shared library (cgo); `bruig/golibbuilder` has per-platform `go generate`
  targets. Dart code is under `bruig/flutterui/bruig/lib`.
- `brseeder/` / `brrtdtserver/` — auxiliary servers (seeder, RTDT server).

## Conventions

- Run `./goclean.sh` before committing; it runs tests, `golangci-lint`, and
  `protolint` — the same gates CI enforces (`.github/workflows/`).
- After changing `clientrpc.proto` or the svcintf generator, regenerate bindings
  and commit the result (CI rejects a dirty regen).
- After bumping protocol behavior, keep the `doc/` protocol descriptions in sync.

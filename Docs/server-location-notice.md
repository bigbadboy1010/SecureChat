# SecureChat Server Code — Location Notice

The SecureChat **relay-server** code is no longer in this public
repository.

- **Client (iOS app)**: still here, AGPL-3.0, public
- **Relay server**: now in a **private** repository
  (`bigbadboy1010/securechat-server-private`)

## Why?

The relay implements routing, peer-authentication, and
rate-limiting logic. Keeping that code public would allow
anyone to spin up a clone-relay and impersonate the SecureChat
network — putting users at risk.

This is consistent with how Signal, Matrix, and Wire handle
their infrastructure code: client open-source, server private.

## Where the code lives now

The relay code, Docker setup, and deploy scripts are in the
Operator's private infrastructure repository. Access is
restricted to authorized operators.

## What if I want to run my own relay?

That is **not** a supported use-case under this license. If you
want to build a fork, the protocol specification is documented
in `docs/protocol.md` and you can implement a compatible server
from scratch — that work would be your own, not derived from
this repository.

## Questions?

Open an issue in this repo (the public client) for client-side
questions. Relay-server questions are not answered publicly.
# PrivateChat Phase 3.1 Changelog

## Fixes

- Fixed Relay ACK/DELETE requests from iOS by removing `Content-Type: application/json` from body-less requests.
- Kept `Content-Type: application/json` only for JSON body requests such as `POST /v1/relay/messages`.
- Hardened Relay server JSON parsing so empty `application/json` ACK/DELETE requests are accepted as `{}` instead of poisoning the route before it executes.
- Hardened Relay server error handling for Fastify 4xx parser errors.
- Hardened Relay ACK handler so store-level ACK races do not poison the client sync loop.

## Why

Fastify rejects empty JSON requests when `Content-Type: application/json` is set but no body is sent. Earlier iOS builds sent that header for ACK/DELETE requests without a body, which caused the Relay to return HTTP errors even though POST/GET worked. Phase 3.1 fixes the client and makes the server tolerant of older clients.

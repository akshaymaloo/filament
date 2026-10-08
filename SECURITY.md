# Security Policy

## Supported versions

Only the latest release of Filament is supported with security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities. Instead,
report it privately using [GitHub Security Advisories](https://github.com/akshaymaloo/filament/security/advisories/new)
for this repository.

Please include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce, ideally including a sample file that triggers it.
- Any relevant macOS / Filament version information.

We'll acknowledge reports as soon as possible and keep you updated as a fix
is developed.

## Scope

Filament's `FilamentKit` library parses untrusted, attacker-controllable
files (`.3mf`/ZIP-OPC archives, STL, OBJ, and PLY) inside a sandboxed macOS
app and Quick Look extensions. Parsing already guards against malformed and
hostile inputs (oversized archives, decompression/"zip bomb" ratios,
out-of-range indices, overflowing numbers, and similar issues) — reports of
crashes, hangs, excessive resource use, or memory-safety issues triggered by
a crafted file are very welcome and treated as security issues.

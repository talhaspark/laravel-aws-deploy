# Architecture

## Request path

```mermaid
flowchart LR
    U[Users] --> D[DNS]
    D --> CF[CloudFront / CDN<br/>optional]
    CF --> N[Nginx]
    N --> P[PHP-FPM]
    P --> L[Laravel app<br/>current release]
    L --> DB[(MySQL / RDS)]
    L --> S3[(S3<br/>files & assets)]
```

## Delivery path

```mermaid
flowchart LR
    G[Push to main] --> T[GitHub Actions: test]
    T --> B[Build: composer, assets, package]
    B --> U[Upload over SSH]
    U --> R[deploy.sh on server]
    R --> M[migrate + cache]
    M --> S[Atomic symlink switch]
    S --> H{Health check}
    H -- pass --> K[Prune old releases]
    H -- fail --> RB[Roll back to previous release]
```

## Server layout

```
/var/www/app
├── current -> releases/20261008120000-ab12cd3   # Nginx serves this
├── releases/
│   ├── 20261008120000-ab12cd3/
│   └── 20261007093000-98ef76a/
└── shared/
    ├── .env          # linked into every release
    └── storage/      # linked into every release (logs, cache, uploads)
```

## Why it is built this way

- **Build in CI, not on the server.** The server never needs Composer, Node or
  Git credentials, so there is less to secure and less to break.
- **Releases in separate directories.** A deploy never edits live files, so a
  half-finished deploy cannot serve a broken mix of old and new code.
- **Atomic symlink switch.** Traffic moves to the new release in one step.
  Rollback is the same step in reverse.
- **`$realpath_root` in Nginx.** Without it, PHP-FPM and OPcache can keep
  serving the old release after the symlink changes.
- **Migrations run before the switch.** If a migration fails, the old release is
  still live. The consequence is that migrations must stay backward-compatible
  for one release (add columns before using them, drop them a release later).

# Workbench temporary CI bridge

This public repository contains only a manually triggered test harness. The application source remains in a private repository and is checked out transiently at one reviewed commit. No source archives, build artifacts, caches, credentials, or production data are published here.

The bridge is temporary until the private repository's included Actions minutes reset. Only the unified-release operator dispatches it for a reviewed exact commit. The private repository's read-only deploy key is held as an Actions secret and must be revoked when the bridge is retired.

# docker-unbound

Unbound is a lightweight caching recursive DNS resolver with DNSSEC and DNS-over-TLS support.

## Environment variables

All options are optional; defaults are used when unset.

### Server options

- `UNBOUND__SERVER__PORT` (default: `5353`)
- `UNBOUND__SERVER__USERNAME` (default: empty)
  - empty disables user/group switch inside Unbound
- `UNBOUND__SERVER__DIRECTORY` (default: `/var/unbound`)
- `UNBOUND__SERVER__CHROOT` (default: empty)
- `UNBOUND__SERVER__AUTO_TRUST_ANCHOR_FILE` (default: `/var/unbound/root.key`)
  - empty disables auto trust anchor generation
- `UNBOUND__SERVER__INTERFACE` (default: `0.0.0.0`)
- `UNBOUND__SERVER__DO_IP4` (default: `yes`)
- `UNBOUND__SERVER__DO_IP6` (default: `no`)
- `UNBOUND__SERVER__DO_UDP` (default: `yes`)
- `UNBOUND__SERVER__DO_TCP` (default: `yes`)
- `UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST` (default: `yes`)
- `UNBOUND__SERVER__USE_CAPS_FOR_ID` (default: `yes`)
- `UNBOUND__SERVER__PREFETCH` (default: `yes`)
- `UNBOUND__SERVER__PREFETCH_KEY` (default: `yes`)
- `UNBOUND__SERVER__QNAME_MINIMISATION` (default: `yes`)
- `UNBOUND__SERVER__MINIMAL_RESPONSES` (default: `yes`)
- `UNBOUND__SERVER__HIDE_IDENTITY` (default: `yes`)
- `UNBOUND__SERVER__HIDE_VERSION` (default: `yes`)
- `UNBOUND__SERVER__HARDEN_GLUE` (default: `yes`)
- `UNBOUND__SERVER__HARDEN_DNSSEC_STRIPPED` (default: `yes`)
- `UNBOUND__SERVER__HARDEN_REFERRAL_PATH` (default: `yes`)
- `UNBOUND__SERVER__HARDEN_ALGO_DOWNGRADE` (default: `yes`)
- `UNBOUND__SERVER__NUM_THREADS` (default: `2`)
- `UNBOUND__SERVER__SO_RCVBUF` (default: `0`)
- `UNBOUND__SERVER__SO_SNDBUF` (default: `0`)
- `UNBOUND__SERVER__CACHE_MIN_TTL` (default: `60`)
- `UNBOUND__SERVER__CACHE_MAX_TTL` (default: `86400`)
- `UNBOUND__SERVER__MSG_CACHE_SIZE` (default: `64m`)
- `UNBOUND__SERVER__RRSET_CACHE_SIZE` (default: `64m`)
- `UNBOUND__SERVER__UNWANTED_REPLY_THRESHOLD` (default: `10000`)
- `UNBOUND__SERVER__VERBOSITY` (default: `1`)
- `UNBOUND__SERVER__LOG_QUERIES` (default: `yes`)
- `UNBOUND__SERVER__USE_SYSLOG` (default: `no`)
- `UNBOUND__SERVER__LOGFILE` (default: `""`, logs to stdout)

### Forward zone options

- `UNBOUND__FORWARD_ZONE__FORWARD_ADDR` (optional)
  - required to enable `forward-zone`
  - supports `IP@PORT` or `HOSTNAME@PORT`
- `UNBOUND__FORWARD_ZONE__NAME` (default: `.`)
- `UNBOUND__FORWARD_ZONE__FORWARD_TLS_UPSTREAM` (default: `no`)
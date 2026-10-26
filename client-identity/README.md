# FP-66 trusted client identity — local candidate, not activated

The backend no longer trusts a numeric proxy-hop count. Default `CLIENT_IP_MODE=socket` ignores forwarding headers and cannot qualify a request for future login exemptions. The existing shared gateway bucket can remain until the edge contract is configured; this default alone does not fix production visitor separation.

`CLIENT_IP_MODE=authenticated-edge` requires a protected random base64url key of at least 32 bytes in `CLIENT_IP_PROXY_KEY`. Caddy supplies the same value from `FRESHPRICE_PROXY_KEY` and overwrites `X-FreshPrice-Client-IP` with `{client_ip}`. The backend validates the key with a constant-time comparison, rejects missing/invalid/duplicate assertions, normalizes exact IPv4/IPv6 identity, removes the credential before downstream middleware, and supplies the verified identity to every existing IP limiter. Normal passwords, roles and sessions remain required. This is an edge assertion credential, not a testing exemption.

The global snippet trusts only operator-reviewed current CDN CIDRs and parses forwarding chains right-to-left. Obtain the current public ranges from https://www.cloudflare.com/ips/; do not trust Docker/private subnets or arbitrary caller headers. Direct-origin traffic through Caddy uses its actual socket peer rather than caller-supplied CDN headers. Direct access to nginx/Next/backend without Caddy's credential is rejected in authenticated-edge mode. Keep backend unpublished and app origin ports protected; the header is not a substitute for network isolation. Protect Caddy's config/admin endpoint, disable request-header debug logging and never export adapted config containing the key.

The exact GET/HEAD `/api/platform/db/health` remains available for container readiness without an edge assertion and never supplies verified identity. No other path or method has this exception.

## Release sequence (not executed)

1. Review and test the backend plus both actual proxy paths first. Use synthetic credentials only in local tests. No production key is included here.
2. Deploy the compatible backend in socket mode with all login exemptions disabled. Budget/report internal requests still work in this mode. Header-dependent `req.protocol` callers must be checked before release because Express proxy trust is disabled.
3. Preserve the active Caddy config, then merge the global snippet and both per-proxy snippets without replacing maintenance/TLS settings. Set protected Caddy environment values, validate configuration with the installed Caddy version and test both sites. `FRESHPRICE_CDN_CIDRS` must be nonempty, reviewed public CDN ranges; the snippets are not an automatic installer.
4. Only after both nginx and Next rewrite paths preserve the assertions, set the backend's protected key and authenticated-edge mode in a targeted service update. Changing a local `.env` alone does not update an existing Swarm service; the current image-only backend workflow does not reconcile new environment values.
5. Verify two independent real public clients and forged forwarding/custom headers through both sites and direct-origin paths. Check DB health, auth, public content and internal server-side API consumers. Server-side consumers need an explicit safe route/identity policy before strict mode can ship; do not distribute a visitor-assertion credential to browser bundles or blindly assert the server's IP as a tester.
6. Roll back mode to socket if required; never enable exemptions or broaden subnet/header trust as a recovery shortcut. Retain existing PostgreSQL guard/firewall and serialized image verification.

The October 23 candidate now implements persisted own-account controls and the FreshPrice admin UI. `AUTH_TEST_EXEMPTIONS_ENABLED=false` remains the default. Every mutation requires a fresh current password; duration defaults to one hour and is bounded to four hours. No live exemption is created.

A distinct `CONTENT_INTERNAL_API_KEY` is shared only by backend and the PhilWatch server. It authorizes exact public content GET/HEAD routes and cannot assert a visitor, reach auth/admin or qualify for exemptions. The `server-only` content helper adds it to internal reads; browser modules never receive it. Public Caddy/nginx paths strip it. Sugilanon's explicit environment deliberately excludes the edge assertion key and database credentials. Both nginx configs and Next's production rewrite preserve Caddy assertions; the production rewrite defaults to the Swarm backend service name.

Local proxy/SSR and database/browser evidence is recorded in the instructions FP-66 continuation. Installed production Caddy/current CDN range validation, protected credential/service rollout, backup/migration recovery and two independent real public-client checks remain release gates. Synthetic local fixtures must never be applied to production.

References: https://caddyserver.com/docs/caddyfile/options (trusted_proxies_strict, client_ip_headers); https://caddyserver.com/docs/caddyfile/directives/reverse_proxy (header_up).

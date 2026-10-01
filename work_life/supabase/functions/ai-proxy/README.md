# AI proxy

Deploy this Supabase Edge Function with JWT verification enabled. Set
`AIMLAPI_KEY` as a Supabase function secret; never place it in Flutter
configuration. Optional server-only configuration: `AIMLAPI_BASE_URL`.

```sh
supabase secrets set AIMLAPI_KEY=...
supabase functions deploy ai-proxy --no-verify-jwt=false
```

The function also verifies the bearer token against Supabase Auth, validates
the operation and provider request shape, limits request bodies to 7 MB, and
times out upstream requests after 30 seconds.

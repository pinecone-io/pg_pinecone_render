# pg_pinecone on Render

PostgreSQL 18 with [pg_pinecone](https://github.com/pinecone-io/pg_pinecone) already installed, as a private service on Render. The database is not on the public internet. Other services in the same workspace and region connect over the [private network](https://render.com/docs/private-network).

Image: [`docker.io/pineconeteam/pg_pinecone:pg18`](https://hub.docker.com/r/pineconeteam/pg_pinecone). `pg18` is the moving tag. A pinned tag exists (`0.11.0-pg18`, and newer version tags beside it). This blueprint uses `pg18` so a redeploy can pick up the current Postgres 18 image. Render does not pull a new digest until the next deploy.

## Deploy to Render

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/pinecone-io/pg_pinecone_render)

`autoDeployTrigger` is `off`, which is the field the [Deploy to Render button](https://render.com/docs/deploy-to-render) docs use. Pushes to the blueprint repository should not redeploy every database created from the button. For a prebuilt image, Render also documents that this field does not change image pulls. It is set because the button docs require it.

## What you get

- Private service `pg-pinecone` (`type: pserv`). No public address, no TLS, no HTTP health check.
- Public image, no registry credential.
- 1 GB disk mounted at `/var/lib/postgresql`. Postgres 18 stores the cluster in `/var/lib/postgresql/18/docker`, which is on that disk.
- Plan `0.5c-512mb` (0.5 CPU, 512 MB). On the [Render pricing page](https://render.com/pricing) this is $7 per month. A persistent disk is $0.25 per GB per month, so the 1 GB disk is $0.25 per month. Together that is $7.25 per month before bandwidth. This is the smallest disk the Blueprint schema allows (`sizeGB` minimum 1) and the cheapest plan that can run a private service with a disk. There is no free plan for private services, and a disk cannot attach to a free instance.
- `POSTGRES_USER=postgres`, database `pg_pinecone`.
- A URL-safe password, generated on first boot and stored on the disk. Render's `generateValue` is still a base64 256-bit string (the docs show a value ending in `=`), and `+`, `/`, and `=` break a connection URL. The start command does not use `generateValue`.

`maxShutdownDelaySeconds` is omitted. Railway waits 60 seconds so Postgres can checkpoint, and Render's usual default is 30, but `render blueprints validate` rejects the field when a disk is attached: "max shutdown delay is not supported for services with a disk". That matches the [disk docs](https://render.com/docs/disks), so this blueprint leaves the delay at Render's default.

## Connect

Postgres listens on port **5432** inside the private network. The image has no TLS, so do not publish that port to the internet.

A Blueprint cannot build the full connection URL. Render does not interpolate variables, and a private service has no `connectionString` property (`connectionString` is only for Render Postgres and Key Value). For a private service, `fromService` supports `host`, `port`, and `hostport`, plus `envVarKey` to copy an environment variable. `port` is documented as the HTTP server port. This database is not an HTTP server, so the URL below uses 5432 rather than that property.

On another service in the same Blueprint:

```yaml
envVars:
  - key: PG_PINECONE_HOST
    fromService:
      name: pg-pinecone
      type: pserv
      property: host
```

Then build the URL in that service's start command. Render can supply the host. It cannot supply the password, because the password is created on the disk rather than by `generateValue`.

```sh
# In the pg-pinecone Shell:
#   cat /var/lib/postgresql/.pg_pinecone_password
#   cat /var/lib/postgresql/.private_database_url

export DATABASE_URL="postgresql://postgres:${PG_PINECONE_PASSWORD}@${PG_PINECONE_HOST}:5432/pg_pinecone"
```

Paste the password into `PG_PINECONE_PASSWORD` on the app service. The password file is mode 600 on the disk and is created once. Later boots reuse it, including after a redeploy. The init SQL runs only when the data directory is empty, so a redeploy does not create the extensions again.

`PRIVATE_HOST` on the database service is a self-reference to `fromService` property `host`. The start command writes `.private_database_url` from that hostname, the password, user `postgres`, database `pg_pinecone`, and port 5432. It is not named `PGHOST`. Libpq reads `PGHOST`, and a value there sends the entrypoint's own clients to the wrong place.

From your computer, the service has no public URL. Use the [Render Shell or SSH](https://render.com/docs/ssh). The official entrypoint removes every `POSTGRES_*` variable before the server process starts, and this blueprint does not put the password in Render's environment, so the Shell will not have `POSTGRES_PASSWORD`. Local socket connections inside the container are trust authentication, so `psql -U postgres -d pg_pinecone` works there. Other services connect over TCP and need the password.

If Render injects `PORT`, `PGHOST`, or `PGPORT`, the start command logs the value and unsets that variable before Postgres starts. The listen port stays 5432.

## Quickstart

```sql
CREATE TABLE items (
    id bigint PRIMARY KEY,
    embedding vector(3)
);

INSERT INTO items VALUES (1, '[1,2,3]'), (2, '[4,5,6]'), (3, '[7,8,9]');

SELECT pinecone.create_index('items', 'embedding');

SELECT id FROM items ORDER BY embedding <=> '[1,2,4]' LIMIT 2;
```

That search runs inside Postgres. The expected ids are 1 and 2.

`vector` and `pg_pinecone` are created the first time the data directory is empty. `shared_preload_libraries` includes `pg_pinecone`, which the remote-engine worker needs.

A Pinecone API key is optional. Store one with `SELECT pinecone.set_api_key('...');` when you want a remote backend, `embed()`, keyword search, search that combines keywords with vectors, or `rerank()`. The quickstart does not need a key.

## Listing copy

`template-page.md` is the draft for a page on [render.com/templates](https://render.com/templates). Publishing that page, and moving this repository to the org Render uses for examples, is still to do.

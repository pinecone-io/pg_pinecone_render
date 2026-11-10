# Start script for the Render service.
# render.yaml runs this file by base64-decoding it. Render rewrites
# ${VAR sequences in a Docker command before the shell runs, so the
# command stored in the blueprint cannot contain them.
set -eu
log_var() {
  if printenv "$1" >/dev/null 2>&1; then
    printf 'pg_pinecone_env %s=%s\n' "$1" "$(printenv "$1")"
  else
    printf 'pg_pinecone_env %s=<unset>\n' "$1"
  fi
}
log_var PORT
log_var PGHOST
log_var PGPORT
log_var RENDER_SERVICE_NAME
log_var RENDER_DISCOVERY_SERVICE
log_var RENDER_EXTERNAL_HOSTNAME
log_var RENDER_SERVICE_TYPE
log_var PRIVATE_HOST
log_var POSTGRES_USER
log_var POSTGRES_DB
printf 'pg_pinecone_env_names='
env | cut -d= -f1 | sort | tr '\n' ' '
printf '\n'
unset_if_set() {
  if printenv "$1" >/dev/null 2>&1; then
    printf 'pg_pinecone_unset %s\n' "$1"
    unset "$1"
  fi
}
unset_if_set PORT
unset_if_set PGHOST
unset_if_set PGPORT
pass_file=/var/lib/postgresql/.pg_pinecone_password
if [ ! -s "$pass_file" ]; then
  umask 077
  if ! printenv POSTGRES_PASSWORD >/dev/null 2>&1 || [ -z "$(printenv POSTGRES_PASSWORD)" ]; then
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -hex 32 | tr -d '\n' > "$pass_file"
    else
      od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$pass_file"
    fi
  else
    pw=$(printenv POSTGRES_PASSWORD)
    case "$pw" in
      *[!A-Za-z0-9_-]*)
        echo "POSTGRES_PASSWORD must contain only letters, digits, hyphen, and underscore." >&2
        exit 1
        ;;
    esac
    printf '%s' "$pw" > "$pass_file"
  fi
  umask 022
  test -s "$pass_file"
fi
POSTGRES_PASSWORD=$(tr -d '\n' < "$pass_file")
export POSTGRES_PASSWORD
chown postgres:postgres "$pass_file"
chmod 600 "$pass_file"
umask 022
mkdir -p /docker-entrypoint-initdb.d
printf '%s\n' 'CREATE EXTENSION IF NOT EXISTS vector;' 'CREATE EXTENSION IF NOT EXISTS pg_pinecone;' > /docker-entrypoint-initdb.d/00-pg-pinecone.sql
chmod 644 /docker-entrypoint-initdb.d/00-pg-pinecone.sql
if printenv PRIVATE_HOST >/dev/null 2>&1 && [ -n "$(printenv PRIVATE_HOST)" ]; then
  user=$(printenv POSTGRES_USER || true)
  db=$(printenv POSTGRES_DB || true)
  [ -n "$user" ] || user=postgres
  [ -n "$db" ] || db=pg_pinecone
  host=$(printenv PRIVATE_HOST)
  printf 'postgresql://%s:%s@%s:5432/%s\n' "$user" "$POSTGRES_PASSWORD" "$host" "$db" > /var/lib/postgresql/.private_database_url
  chown postgres:postgres /var/lib/postgresql/.private_database_url
  chmod 600 /var/lib/postgresql/.private_database_url
fi
exec docker-entrypoint.sh postgres -c shared_preload_libraries=pg_pinecone --port=5432

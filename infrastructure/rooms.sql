-- Planned shared-store schema for multi-process room ownership.
-- Runtime currently uses atomic JSON snapshots and a single-owner lock.
create table if not exists tractor_rooms (
  code text primary key,
  payload jsonb not null,
  revision bigint not null,
  match_revision bigint not null,
  touched_at timestamptz not null default now()
);

create table if not exists tractor_room_events (
  code text not null references tractor_rooms(code) on delete cascade,
  revision bigint not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (code, revision)
);

create index if not exists tractor_room_events_poll
  on tractor_room_events (code, revision);

-- 2026 워크샵 투표 (ws26_ 테이블만 사용, 다른 테이블과 무관)
create table if not exists public.ws26_state (id int primary key default 1, data jsonb not null default '{}'::jsonb);
create table if not exists public.ws26_secret (id int primary key default 1, pin text not null);
create table if not exists public.ws26_ballots (
  round text not null, voter text not null, token text not null,
  course text, venue text, updated_at timestamptz not null default now(),
  primary key (round, voter)
);
alter table public.ws26_state enable row level security;
alter table public.ws26_secret enable row level security;
alter table public.ws26_ballots enable row level security;
revoke all on public.ws26_state, public.ws26_secret, public.ws26_ballots from anon, authenticated;

insert into public.ws26_state(id,data) values (1,'{"round":"r1","threshold":2,"names":[],"forced_c":false,"forced_p":false,"final_c":null,"final_p":null,"budget":"","deadline":""}'::jsonb)
on conflict (id) do nothing;
insert into public.ws26_secret(id,pin) values (1,'여기에_PIN') on conflict (id) do nothing; -- 이미 PIN이 있으면 바꾸지 않습니다

create or replace function public.ws26_status(p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st jsonb; r text; th int; cn int; pn int; c_rev bool; p_rev bool; cc jsonb; pc jsonb; me jsonb; voted_c jsonb; voted_p jsonb;
begin
  select data into st from ws26_state where id = 1;
  r := coalesce(st->>'round','r1'); th := coalesce((st->>'threshold')::int,10);
  select count(*) into cn from ws26_ballots where round = r and course is not null;
  select count(*) into pn from ws26_ballots where round = r and venue is not null;
  c_rev := cn >= th or coalesce((st->>'forced_c')::bool,false);
  p_rev := pn >= th or coalesce((st->>'forced_p')::bool,false);
  if c_rev then
    select coalesce(jsonb_object_agg(course, n), '{}'::jsonb) into cc
    from (select course, count(*) n from ws26_ballots where round = r and course is not null group by course) t;
  end if;
  if p_rev then
    select coalesce(jsonb_object_agg(venue, n), '{}'::jsonb) into pc
    from (select venue, count(*) n from ws26_ballots where round = r and venue is not null group by venue) t;
  end if;
  if p_token is not null then
    select jsonb_build_object('name', voter, 'course', course, 'venue', venue) into me
    from ws26_ballots where round = r and token = p_token limit 1;
  end if;
  select coalesce(jsonb_agg(voter order by voter), '[]'::jsonb) into voted_c from ws26_ballots where round = r and course is not null;
  select coalesce(jsonb_agg(voter order by voter), '[]'::jsonb) into voted_p from ws26_ballots where round = r and venue is not null;
  return jsonb_build_object('round', r, 'threshold', th, 'names', coalesce(st->'names','[]'::jsonb),
    'budget', coalesce(st->>'budget',''), 'deadline', coalesce(st->>'deadline',''),
    'forced_c', coalesce((st->>'forced_c')::bool,false), 'forced_p', coalesce((st->>'forced_p')::bool,false),
    'final_c', st->>'final_c', 'final_p', st->>'final_p',
    'cN', cn, 'pN', pn, 'cRev', c_rev, 'pRev', p_rev, 'cCounts', cc, 'pCounts', pc, 'me', me,
    'votedC', voted_c, 'votedP', voted_p);
end $$;

create or replace function public.ws26_vote(p_name text, p_token text, p_kind text, p_value text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st jsonb; r text; th int; cn int; pn int; ex record; c1 int; c2 int; win text; crev bool;
begin
  if p_token is null or length(p_token) < 16 then raise exception 'bad_token'; end if;
  perform pg_advisory_xact_lock(2026);
  select data into st from ws26_state where id = 1;
  r := coalesce(st->>'round','r1'); th := coalesce((st->>'threshold')::int,10);
  if not (coalesce(st->'names','[]'::jsonb) ? p_name) then raise exception 'unknown_name'; end if;
  select * into ex from ws26_ballots where round = r and voter = p_name;
  if found and ex.token <> p_token then raise exception 'name_taken'; end if;
  if exists (select 1 from ws26_ballots where round = r and token = p_token and voter <> p_name) then raise exception 'token_used'; end if;
  select count(*) into cn from ws26_ballots where round = r and course is not null;
  select count(*) into pn from ws26_ballots where round = r and venue is not null;
  crev := cn >= th or coalesce((st->>'forced_c')::bool,false);
  if p_kind = 'course' then
    if p_value not in ('c1','c2') then raise exception 'bad_value'; end if;
    if crev then raise exception 'closed'; end if;
    insert into ws26_ballots(round, voter, token, course) values (r, p_name, p_token, p_value)
    on conflict (round, voter) do update set course = excluded.course, updated_at = now();
  elsif p_kind = 'venue' then
    if p_value not in ('thek','camp','loopl') then raise exception 'bad_value'; end if;
    select count(*) filter (where course = 'c1'), count(*) filter (where course = 'c2') into c1, c2 from ws26_ballots where round = r;
    win := coalesce(st->>'final_c', case when c1 > c2 then 'c1' when c2 > c1 then 'c2' else 'tie' end);
    if not (crev and win = 'c2') then raise exception 'party_closed'; end if;
    if pn >= th or coalesce((st->>'forced_p')::bool,false) then raise exception 'closed'; end if;
    insert into ws26_ballots(round, voter, token, venue) values (r, p_name, p_token, p_value)
    on conflict (round, voter) do update set venue = excluded.venue, updated_at = now();
  else
    raise exception 'bad_kind';
  end if;
  return ws26_status(p_token);
end $$;

create or replace function public.ws26_admin(p_pin text, p_action text, p_value jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from ws26_secret where id = 1 and pin = p_pin) then raise exception 'bad_pin'; end if;
  if p_action = 'check' then
    null;
  elsif p_action in ('threshold','names','budget','deadline','forced_c','forced_p','final_c','final_p') then
    update ws26_state set data = jsonb_set(data, array[p_action], coalesce(p_value, 'null'::jsonb), true) where id = 1;
  elsif p_action = 'new_round' then
    update ws26_state set data = data || jsonb_build_object('round', 'r' || floor(extract(epoch from now()))::bigint,
      'forced_c', false, 'forced_p', false, 'final_c', null, 'final_p', null) where id = 1;
  elsif p_action = 'reset_flags' then
    update ws26_state set data = data || jsonb_build_object('forced_c', false, 'forced_p', false, 'final_c', null, 'final_p', null) where id = 1;
  else
    raise exception 'bad_action';
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.ws26_status(text), public.ws26_vote(text,text,text,text), public.ws26_admin(text,text,jsonb) from public;
grant execute on function public.ws26_status(text), public.ws26_vote(text,text,text,text), public.ws26_admin(text,text,jsonb) to anon, authenticated;
select public.ws26_status(null);

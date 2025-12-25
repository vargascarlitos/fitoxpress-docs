-- =========================================
--  EXTENSIONES Y ESQUEMAS
-- =========================================
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "postgis";

create schema if not exists ref;
create schema if not exists core;
create schema if not exists ops;
create schema if not exists billing;
create schema if not exists ingest;
create schema if not exists audit;
create schema if not exists stg;

-- =========================================
--  ENUMS GLOBALES
-- =========================================
do $$ begin
  if not exists (select 1 from pg_type where typname = 'merchant_tariff_mode') then
    create type merchant_tariff_mode as enum ('standard','custom');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type app_role as enum ('admin','operator','merchant','rider');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'delivery_status') then
    create type delivery_status as enum ('recepcionado','en_transito','entregado','rechazado_puerta','cancelado_previo','reagendado','extraviado');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'cash_status') then
    create type cash_status as enum ('sin_cobro','cobrado');
  end if;
end $$;

-- Estados legacy de order (seguimos teniendo la columna para compatibilidad)
do $$ begin
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type "core"."order_status" as enum ('draft','created','assigned','picked_up','en_route','delivered','failed','canceled');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'vehicle_type') then
    create type "ops"."vehicle_type" as enum ('motorcycle','car','bicycle','on_foot');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'assignment_status') then
    create type "ops"."assignment_status" as enum ('pending','accepted','picked_up','en_route','delivered','failed','canceled');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type "billing"."payment_method" as enum ('cash','pos','transfer','gateway');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type "billing"."payment_status" as enum ('pending','paid','failed','refunded');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'settlement_status') then
    create type "billing"."settlement_status" as enum ('open','paid','canceled');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'media_type') then
    create type "ingest"."media_type" as enum ('none','image','audio','video','document','location');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'parse_status') then
    create type "ingest"."parse_status" as enum ('pending','parsed','needs_review','rejected');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'bank_account_type') then
    create type "core"."bank_account_type" as enum ('normal','alias');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'bank_alias_type') then
    create type "core"."bank_alias_type" as enum ('celular','correo','cedula_identidad','ruc','persona_fisica_no_residente','carnet_residencia');
  end if;
end $$;

-- =========================================
--  REF: CIUDADES / ZONAS / TARIFAS ESTÁNDAR
-- =========================================
create table if not exists ref.city (
  id serial primary key,
  name text NOT NULL,
  department text,
  department_norm text GENERATED ALWAYS AS (coalesce(department, '')) STORED,
  UNIQUE (name, department_norm)
);

create table if not exists ref.zone (
  id          bigserial primary key,
  city_id     bigint not null references ref.city(id) on delete cascade,
  name        text not null,
  polygon     geometry,
  is_active   boolean not null default true,
  unique (city_id, name)
);

create table if not exists ref.city_rate (
  id             bigserial primary key,
  city_id        bigint not null references ref.city(id) on delete cascade,
  amount_gs      integer not null check (amount_gs > 0),
  effective_from date not null default current_date,
  effective_to   date,
  unique (city_id, effective_from)
);

create table if not exists ref.zone_rate (
  id             bigserial primary key,
  zone_id        bigint not null references ref.zone(id) on delete cascade,
  amount_gs      integer not null check (amount_gs > 0),
  effective_from date not null default current_date,
  effective_to   date,
  unique (zone_id, effective_from)
);

create table if not exists ref.city_alias (
  id      bigserial primary key,
  city_id bigint not null references ref.city(id) on delete cascade,
  alias   text not null
);

create unique index if not exists uq_city_alias_city_alias_lower
  on ref.city_alias (city_id, lower(alias));

create index if not exists ix_city_alias_alias on ref.city_alias (lower(alias));

-- =========================================
--  CORE: PERFILES Y COMERCIOS
-- =========================================
create table if not exists core.user_profile (
  auth_user_id  uuid primary key,             -- auth.users.id
  role          app_role not null,
  full_name     text,
  phone         text,
  created_at    timestamptz not null default now(),
  is_active     boolean not null default true,
  password_change_required boolean not null default false
);

create table if not exists core.merchant (
  id                      uuid primary key default gen_random_uuid(),
  name                    text not null,
  ruc                     text,
  phone                   text,
  email                   text,
  auth_user_id            uuid,         -- referencia a auth.users
  tariff_mode             merchant_tariff_mode not null default 'standard',
  allow_tariff_fallback   boolean not null default true,
  is_active               boolean not null default true,
  created_at              timestamptz not null default now()
);

create table if not exists core.bank_account (
  id              uuid primary key default gen_random_uuid(),
  merchant_id     uuid not null references core.merchant(id) on delete cascade,
  account_type    core.bank_account_type not null,
  is_default      boolean not null default false,
  -- Cuenta tipo 'normal'
  holder_name     text,                    -- Titular
  bank_name       text,                    -- Nombre del banco
  document_number text,                    -- Nro documento del titular
  account_number  text,                    -- Nro de cuenta
  -- Cuenta tipo 'alias'
  alias_type      core.bank_alias_type,    -- Tipo de alias SIPAP
  alias_value     text,                    -- Valor del alias
  -- Metadata
  label           text,                    -- Etiqueta opcional
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  -- Validaciones
  constraint chk_normal_account_fields check (
    account_type != 'normal' or (holder_name is not null and bank_name is not null and account_number is not null)
  ),
  constraint chk_alias_account_fields check (
    account_type != 'alias' or (alias_type is not null and alias_value is not null)
  )
);

create unique index if not exists uq_bank_account_merchant_default
  on core.bank_account (merchant_id) where is_default = true;

create index if not exists ix_bank_account_merchant
  on core.bank_account (merchant_id);

create table if not exists core.address (
  id              uuid primary key default gen_random_uuid(),
  label           text,
  street          text,
  number          text,
  neighborhood    text,
  city_id         bigint references ref.city(id),
  zone_id         bigint references ref.zone(id),
  reference_notes text,
  location        geometry(Point,4326),
  created_at      timestamptz not null default now(),
  google_maps_url text  -- URL de Google Maps o Waze para facilitar la ubicación
);

create table if not exists core.contact (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null,
  phone       text,
  email       text
);

create table if not exists core.merchant_address (
  merchant_id uuid not null references core.merchant(id) on delete cascade,
  address_id  uuid not null references core.address(id) on delete restrict,
  is_default  boolean not null default false,
  primary key (merchant_id, address_id)
);
create unique index if not exists uq_merchant_default_address
on core.merchant_address (merchant_id) where is_default = true;

create table if not exists core.recipient (
  id              uuid primary key default gen_random_uuid(),
  contact_id      uuid not null references core.contact(id) on delete restrict,
  default_address uuid references core.address(id),
  created_at      timestamptz not null default now()
);

create table if not exists core.product (
  id            uuid primary key default gen_random_uuid(),
  merchant_id   uuid not null references core.merchant(id) on delete cascade,
  name          text not null,
  sku           text,
  unit_price_gs integer,
  is_active     boolean not null default true
);

create unique index if not exists uq_product_merchant_sku_name_lower
  on core.product (merchant_id, coalesce(sku,''), name);

-- =========================================
--  CORE: PEDIDOS
-- =========================================
create table if not exists core."order" (
  id                  uuid primary key default gen_random_uuid(),
  merchant_id         uuid not null references core.merchant(id) on delete restrict,
  external_ref        text,
  recipient_id        uuid not null references core.recipient(id) on delete restrict,
  pickup_address_id   uuid not null references core.address(id),
  dropoff_address_id  uuid not null references core.address(id),
  declared_value_gs   integer default 0,
  cash_to_collect_gs  integer default 0,
  notes               text,
  status              core.order_status not null default 'created', -- legacy
  -- Estados que usás operativamente:
  delivery_status     delivery_status not null default 'recepcionado',
  cash_status         cash_status     not null default 'sin_cobro',
  settled_with_merchant boolean not null default false,
  settled_with_rider    boolean not null default false,
  delivery_window_start timestamptz,
  delivery_window_end   timestamptz,
  requested_at        timestamptz not null default now(),
  due_by              timestamptz,
  created_by_auth     uuid,
  updated_at          timestamptz not null default now(),
  -- Reagendamiento
  scheduled_date      date,                           -- Fecha programada para entrega
  reschedule_count    integer not null default 0      -- Veces que se reagendó
);

create table if not exists core.order_item (
  id            bigserial primary key,
  order_id      uuid not null references core."order"(id) on delete cascade,
  product_id    uuid references core.product(id),
  description   text not null,
  qty           integer not null check (qty > 0),
  unit_price_gs integer default 0
);

create table if not exists core.order_event (
  id            bigserial primary key,
  order_id      uuid not null references core."order"(id) on delete cascade,
  at            timestamptz not null default now(),
  from_status   core.order_status,
  to_status     core.order_status not null,
  actor_auth    uuid,
  notes         text
);

create table if not exists core.order_pod (
  order_id      uuid primary key references core."order"(id) on delete cascade,
  delivered_at  timestamptz,
  receiver_name text,
  signature_url text,
  photo_url     text,
  notes         text
);

comment on table core.bank_account is 'Cuentas bancarias de los comercios para recibir pagos de liquidaciones';
comment on column core.bank_account.account_type is 'Tipo: normal (datos bancarios) o alias (SIPAP)';
comment on column core.bank_account.is_default is 'Si es la cuenta principal del comercio';
comment on column core.bank_account.holder_name is 'Titular de la cuenta (solo para tipo normal)';
comment on column core.bank_account.bank_name is 'Nombre del banco (solo para tipo normal)';
comment on column core.bank_account.document_number is 'Nro documento del titular (solo para tipo normal)';
comment on column core.bank_account.account_number is 'Número de cuenta (solo para tipo normal)';
comment on column core.bank_account.alias_type is 'Tipo de alias SIPAP (solo para tipo alias)';
comment on column core.bank_account.alias_value is 'Valor del alias (solo para tipo alias)';

comment on column core.address.google_maps_url is 'URL de Google Maps o Waze para facilitar la ubicación';
comment on column core."order".scheduled_date is 'Fecha programada para la entrega. Se actualiza cuando el pedido se reagenda.';
comment on column core."order".reschedule_count is 'Contador de veces que el pedido fue reagendado.';
comment on column ops.courier.auth_user_id is 'Usuario de autenticación (obligatorio). Debe existir en user_profile con role=rider.';

-- =========================================
--  TABLA DE NOTAS DE RENDICIÓN
-- =========================================
create table if not exists core.rendition_note (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references core."order"(id) on delete cascade,
  note        text not null,
  created_at  timestamptz default now(),
  created_by  text
);

-- =========================================
--  OPS: RIDERS, ASIGNACIONES, TRACKING
-- =========================================
create table if not exists ops.courier (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null references core.user_profile(auth_user_id) on delete restrict,
  full_name     text not null,
  phone         text,
  vehicle_type  ops.vehicle_type not null,
  plate         text,
  is_active     boolean not null default true,
  hired_at      date,
  created_at    timestamptz not null default now()
);

create table if not exists ops.assignment (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references core."order"(id) on delete cascade,
  courier_id    uuid not null references ops.courier(id) on delete restrict,
  status        ops.assignment_status not null default 'pending',
  assigned_at   timestamptz not null default now(),
  accepted_at   timestamptz,
  picked_up_at  timestamptz,
  delivered_at  timestamptz,
  failed_reason text
);

create table if not exists ops.courier_location (
  id         bigserial primary key,
  courier_id uuid not null references ops.courier(id) on delete cascade,
  at         timestamptz not null default now(),
  location   geometry(Point,4326) not null
);
create index if not exists ix_courier_location on ops.courier_location (courier_id, at desc);

-- Riders habilitados por ciudad / zona
create table if not exists ops.courier_city (
  courier_id uuid not null references ops.courier(id) on delete cascade,
  city_id    bigint not null references ref.city(id) on delete cascade,
  primary key (courier_id, city_id)
);

create table if not exists ops.courier_zone (
  courier_id uuid not null references ops.courier(id) on delete cascade,
  zone_id    bigint not null references ref.zone(id) on delete cascade,
  primary key (courier_id, zone_id)
);

-- Helper: obtener datos del courier autenticado (para app rider)
create or replace function ops.fn_get_my_courier()
returns table (
  courier_id uuid,
  full_name text,
  phone text,
  vehicle_type ops.vehicle_type,
  plate text,
  is_active boolean,
  hired_at date
)
language sql
stable
security definer
as
$$
  select id, full_name, phone, vehicle_type, plate, is_active, hired_at
  from ops.courier
  where auth_user_id = auth.uid();
$$;

-- Helper: validación de elegibilidad
create or replace function ops.fn_courier_can_take(p_order_id uuid, p_courier_id uuid)
returns boolean
language sql
stable
as
$$
with o as (
  select op.city_id, op.zone_id
  from billing.order_pricing op
  where op.order_id = p_order_id
),
ok_zone as (
  select 1
  from ops.courier_zone cz
  join o on o.zone_id = cz.zone_id
  where cz.courier_id = p_courier_id
),
ok_city as (
  select 1
  from ops.courier_city cc
  join o on o.city_id = cc.city_id
  where cc.courier_id = p_courier_id
)
select exists(select 1 from ok_zone) or exists(select 1 from ok_city);
$$;

create or replace function ops.trg_assignment_check_area()
returns trigger
language plpgsql
as
$$
declare v_ok boolean;
begin
  select ops.fn_courier_can_take(NEW.order_id, NEW.courier_id) into v_ok;
  if not coalesce(v_ok, false) then
    raise exception 'Courier % no habilitado para la zona/ciudad del pedido %', NEW.courier_id, NEW.order_id
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_assignment_check_area on ops.assignment;
create trigger trg_assignment_check_area
before insert or update of courier_id, order_id on ops.assignment
for each row execute function ops.trg_assignment_check_area();

-- =========================================
--  BILLING: PRICING, COBROS, LIQUIDACIONES
-- =========================================
create table if not exists billing.order_pricing (
  order_id        uuid primary key references core."order"(id) on delete cascade,
  city_id         bigint references ref.city(id),
  zone_id         bigint references ref.zone(id),
  base_amount_gs  integer check (base_amount_gs >= 0),
  extras_gs       integer not null default 0,
  total_amount_gs integer generated always as (coalesce(base_amount_gs,0) + extras_gs) stored
);

create table if not exists billing.collection (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references core."order"(id) on delete cascade,
  method        billing.payment_method not null,
  status        billing.payment_status not null default 'pending',
  amount_gs     integer not null check (amount_gs >= 0),
  occurred_at   timestamptz not null default now(),
  notes         text
);

-- Al marcar cobro pagado, reflejar en el pedido
create or replace function billing.trg_collection_mark_cobrado()
returns trigger
language plpgsql
as
$$
begin
  if NEW.status = 'paid' then
    update core."order" set cash_status = 'cobrado' where id = NEW.order_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_collection_mark_cobrado on billing.collection;
create trigger trg_collection_mark_cobrado
after insert or update of status on billing.collection
for each row execute function billing.trg_collection_mark_cobrado();

-- Liquidaciones por comercio
create table if not exists billing.settlement (
  id            uuid primary key default gen_random_uuid(),
  merchant_id   uuid not null references core.merchant(id) on delete cascade,
  period_start  date not null,
  period_end    date not null,
  status        billing.settlement_status not null default 'open',
  total_orders  integer not null default 0,
  total_gs      bigint not null default 0,
  run_source    text,
  created_by_auth uuid,
  notes         text,
  created_at    timestamptz not null default now()
);

create table if not exists billing.settlement_item (
  id            bigserial primary key,
  settlement_id uuid not null references billing.settlement(id) on delete cascade,
  order_id      uuid not null references core."order"(id) on delete restrict,
  amount_gs     integer not null
);

-- Protecciones contra duplicados
create unique index if not exists uq_settlement_merchant_day
on billing.settlement (merchant_id, period_start, period_end)
where period_start = period_end;

create unique index if not exists uq_settlement_item_order
on billing.settlement_item (order_id);

-- =========================================
--  TARIFARIO CUSTOM POR COMERCIO + RESOLUCIÓN
-- =========================================
create table if not exists billing.merchant_city_rate (
  id             bigserial primary key,
  merchant_id    uuid not null references core.merchant(id) on delete cascade,
  city_id        bigint not null references ref.city(id) on delete cascade,
  amount_gs      integer not null check (amount_gs > 0),
  effective_from date not null default current_date,
  effective_to   date,
  unique (merchant_id, city_id, effective_from)
);

create table if not exists billing.merchant_zone_rate (
  id             bigserial primary key,
  merchant_id    uuid not null references core.merchant(id) on delete cascade,
  zone_id        bigint not null references ref.zone(id) on delete cascade,
  amount_gs      integer not null check (amount_gs > 0),
  effective_from date not null default current_date,
  effective_to   date,
  unique (merchant_id, zone_id, effective_from)
);

create or replace view billing.v_current_rates as
with
std_city as (
  select city_id, amount_gs from (
    select city_id, amount_gs, effective_from,
           row_number() over (partition by city_id order by effective_from desc) rn
    from ref.city_rate
    where (effective_to is null or effective_to >= current_date)
      and effective_from <= current_date
  ) t where rn = 1
),
std_zone as (
  select zone_id, amount_gs from (
    select zone_id, amount_gs, effective_from,
           row_number() over (partition by zone_id order by effective_from desc) rn
    from ref.zone_rate
    where (effective_to is null or effective_to >= current_date)
      and effective_from <= current_date
  ) t where rn = 1
),
cz as (
  select z.id as zone_id, z.name as zone_name, c.id as city_id, c.name as city_name
  from ref.zone z join ref.city c on c.id = z.city_id
)
select 'standard_city'::text source, null::uuid merchant_id,
       c.id city_id, null::bigint zone_id, c.name city_name, null::text zone_name, sc.amount_gs
from ref.city c left join std_city sc on sc.city_id = c.id
union all
select 'standard_zone', null, cz.city_id, cz.zone_id, cz.city_name, cz.zone_name, sz.amount_gs
from cz left join std_zone sz on sz.zone_id = cz.zone_id;

create or replace function billing.fn_resolve_rate_v2(
  p_merchant_id uuid,
  p_city_id     bigint,
  p_zone_id     bigint default null,
  p_at_date     date   default current_date
)
returns table (
  source    text,     -- 'custom_zone' | 'custom_city' | 'standard_zone' | 'standard_city' | 'not_found'
  amount_gs integer,
  city_id   bigint,
  zone_id   bigint
)
language plpgsql
as
$$
declare
  v_mode     merchant_tariff_mode;
  v_fallback boolean;
  v_amount   integer;
begin
  select tariff_mode, allow_tariff_fallback into v_mode, v_fallback
  from core.merchant where id = p_merchant_id;

  -- custom primero
  if v_mode = 'custom' then
    if p_zone_id is not null then
      select amount_gs into v_amount
      from billing.merchant_zone_rate
      where merchant_id = p_merchant_id and zone_id = p_zone_id
        and effective_from <= p_at_date
        and (effective_to is null or effective_to >= p_at_date)
      order by effective_from desc limit 1;
      if v_amount is not null then
        return query select 'custom_zone', v_amount, p_city_id, p_zone_id; return;
      end if;
    end if;

    select amount_gs into v_amount
    from billing.merchant_city_rate
    where merchant_id = p_merchant_id and city_id = p_city_id
      and effective_from <= p_at_date
      and (effective_to is null or effective_to >= p_at_date)
    order by effective_from desc limit 1;
    if v_amount is not null then
      return query select 'custom_city', v_amount, p_city_id, p_zone_id; return;
    end if;

    if not v_fallback then
      return query select 'not_found', null::integer, p_city_id, p_zone_id; return;
    end if;
  end if;

  -- estándar
  if p_zone_id is not null then
    select amount_gs into v_amount
    from ref.zone_rate
    where zone_id = p_zone_id
      and effective_from <= p_at_date
      and (effective_to is null or effective_to >= p_at_date)
    order by effective_from desc limit 1;
    if v_amount is not null then
      return query select 'standard_zone', v_amount, p_city_id, p_zone_id; return;
    end if;
  end if;

  select amount_gs into v_amount
  from ref.city_rate
  where city_id = p_city_id
    and effective_from <= p_at_date
    and (effective_to is null or effective_to >= p_at_date)
  order by effective_from desc limit 1;
  if v_amount is not null then
    return query select 'standard_city', v_amount, p_city_id, p_zone_id; return;
  end if;

  return query select 'not_found', null::integer, p_city_id, p_zone_id;
end;
$$;

create or replace function billing.trg_order_pricing_fill_v2()
returns trigger language plpgsql
as
$$
declare
  v record;
begin
  if NEW.base_amount_gs is not null and NEW.base_amount_gs > 0 then
    return NEW;
  end if;

  select * from billing.fn_resolve_rate_v2(
    (select merchant_id from core."order" o where o.id = NEW.order_id),
    NEW.city_id,
    NEW.zone_id,
    current_date
  ) into v;

  if v.amount_gs is not null then
    NEW.base_amount_gs := v.amount_gs;
  else
    NEW.base_amount_gs := 0;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_fill_order_pricing on billing.order_pricing;
create trigger trg_fill_order_pricing
before insert on billing.order_pricing
for each row execute function billing.trg_order_pricing_fill_v2();

-- Clonado del tarifario estándar → custom
create or replace function billing.fn_clone_standard_rates(
  p_merchant_id uuid,
  p_effective_from date default current_date,
  p_replace_existing boolean default true
)
returns table (cloned_city_count integer, cloned_zone_count integer)
language plpgsql
as
$$
declare v_city_cnt int := 0; v_zone_cnt int := 0;
begin
  if p_replace_existing then
    delete from billing.merchant_city_rate
    where merchant_id = p_merchant_id
      and (effective_to is null or effective_to >= p_effective_from);
    delete from billing.merchant_zone_rate
    where merchant_id = p_merchant_id
      and (effective_to is null or effective_to >= p_effective_from);
  end if;

  with std_city as (
    select city_id, amount_gs from (
      select city_id, amount_gs, effective_from,
             row_number() over (partition by city_id order by effective_from desc) rn
      from ref.city_rate
      where (effective_to is null or effective_to >= p_effective_from)
        and effective_from <= p_effective_from
    ) t where rn = 1
  )
  insert into billing.merchant_city_rate (merchant_id, city_id, amount_gs, effective_from)
  select p_merchant_id, sc.city_id, sc.amount_gs, p_effective_from
  from std_city sc
  on conflict do nothing;
  get diagnostics v_city_cnt = row_count;

  with std_zone as (
    select zone_id, amount_gs from (
      select zone_id, amount_gs, effective_from,
             row_number() over (partition by zone_id order by effective_from desc) rn
      from ref.zone_rate
      where (effective_to is null or effective_to >= p_effective_from)
        and effective_from <= p_effective_from
    ) t where rn = 1
  )
  insert into billing.merchant_zone_rate (merchant_id, zone_id, amount_gs, effective_from)
  select p_merchant_id, sz.zone_id, sz.amount_gs, p_effective_from
  from std_zone sz
  on conflict do nothing;
  get diagnostics v_zone_cnt = row_count;

  return query select v_city_cnt, v_zone_cnt;
end;
$$;

create or replace function billing.fn_enable_custom_with_clone(
  p_merchant_id uuid,
  p_effective_from date default current_date,
  p_replace_existing boolean default true,
  p_allow_fallback boolean default true
)
returns table (cloned_city_count integer, cloned_zone_count integer)
language plpgsql
as
$$
begin
  update core.merchant
  set tariff_mode = 'custom', allow_tariff_fallback = p_allow_fallback
  where id = p_merchant_id;

  return query
    select * from billing.fn_clone_standard_rates(
      p_merchant_id => p_merchant_id,
      p_effective_from => p_effective_from,
      p_replace_existing => p_replace_existing
    );
end;
$$;

-- =========================================
--  INGESTA WHATSAPP + PARSEO
-- =========================================
create table if not exists ingest.channel (
  id            uuid primary key default gen_random_uuid(),
  provider      text not null default 'whatsapp',
  waba_id       text,
  phone_number  text not null,
  label         text,
  is_active     boolean not null default true,
  unique (phone_number)
);

create table if not exists ingest.channel_merchant (
  channel_id   uuid not null references ingest.channel(id) on delete cascade,
  merchant_id  uuid not null references core.merchant(id) on delete cascade,
  is_default   boolean not null default false,
  primary key (channel_id, merchant_id)
);

create table if not exists ingest.message (
  id            uuid primary key default gen_random_uuid(),
  channel_id    uuid references ingest.channel(id) on delete set null,
  wa_message_id text,
  from_phone    text not null,
  to_phone      text,
  sent_at       timestamptz not null default now(),
  raw_text      text,
  media_type    ingest.media_type not null default 'none',
  media_url     text,
  payload_json  jsonb,
  detected_lang text,
  created_at    timestamptz not null default now(),
  unique (wa_message_id)
);

create table if not exists ingest.message_location (
  id          bigserial primary key,
  message_id  uuid not null references ingest.message(id) on delete cascade,
  lat         double precision not null,
  lon         double precision not null,
  address_text text,
  accuracy_m  double precision
);
create index if not exists ix_msg_loc_message on ingest.message_location (message_id);

create table if not exists ingest.order_intent (
  id                uuid primary key default gen_random_uuid(),
  message_id        uuid not null references ingest.message(id) on delete cascade,
  status            ingest.parse_status not null default 'pending',
  confidence        numeric(5,2) not null default 0.00, -- 0..100
  recipient_name    text,
  recipient_phone   text,
  address_text      text,
  city_id           bigint references ref.city(id),
  location          geometry(Point,4326),
  products_text     text,
  amount_gs         integer,
  notes             text,
  delivery_by       timestamptz,
  window_start      timestamptz,
  window_end        timestamptz,
  errors            jsonb,
  created_at        timestamptz not null default now()
);
create index if not exists ix_oi_status_conf on ingest.order_intent (status, confidence);
create index if not exists ix_oi_city on ingest.order_intent (city_id);

create table if not exists ingest.intent_order_link (
  order_intent_id uuid primary key references ingest.order_intent(id) on delete cascade,
  order_id        uuid not null references core."order"(id) on delete cascade,
  linked_at       timestamptz not null default now(),
  linked_by_auth  uuid
);

create or replace view ingest.v_inbox as
select
  oi.id as order_intent_id,
  m.sent_at,
  m.from_phone,
  m.raw_text,
  oi.status,
  oi.confidence,
  oi.recipient_name,
  oi.recipient_phone,
  oi.address_text,
  oi.amount_gs,
  oi.delivery_by,
  c.name as city_name
from ingest.order_intent oi
join ingest.message m on m.id = oi.message_id
left join ref.city c on c.id = oi.city_id
order by
  case oi.status when 'needs_review' then 0 when 'pending' then 1 when 'parsed' then 2 else 3 end,
  m.sent_at desc;

-- =========================================
--  AUDITORÍA
-- =========================================
create table if not exists audit.event (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  actor_auth uuid,
  entity    text not null,
  entity_id uuid,
  action    text not null, -- 'insert','update','status_change'
  details   jsonb
);

-- =========================================
--  PAGOS A RIDERS (RENDIDO CON RIDER)
-- =========================================
create table if not exists ops.rider_payout (
  id            uuid primary key default gen_random_uuid(),
  courier_id    uuid not null references ops.courier(id) on delete restrict,
  period_start  date not null,
  period_end    date not null,
  total_gs      bigint not null default 0,
  is_paid       boolean not null default false,
  paid_at       timestamptz,
  notes         text,
  created_at    timestamptz not null default now()
);

create table if not exists ops.rider_payout_item (
  id            bigserial primary key,
  payout_id     uuid not null references ops.rider_payout(id) on delete cascade,
  assignment_id uuid not null references ops.assignment(id) on delete restrict,
  amount_gs     integer not null,
  unique (payout_id, assignment_id)
);

create or replace function ops.fn_confirm_rider_payout(p_payout_id uuid)
returns void
language plpgsql
as
$$
begin
  update ops.rider_payout
     set is_paid = true, paid_at = now()
   where id = p_payout_id;

  update core."order" o
     set settled_with_rider = true
    from ops.rider_payout_item pi
    join ops.assignment a on a.id = pi.assignment_id
   where pi.payout_id = p_payout_id
     and a.order_id = o.id;
end;
$$;

-- =========================================
--  VISTAS DE SEGUIMIENTO
-- =========================================
create or replace view ops.v_order_tracking as
select
  o.id as order_id,
  o.merchant_id,
  o.delivery_status,
  o.cash_status,
  o.settled_with_merchant,
  o.settled_with_rider,
  op.total_amount_gs,
  a.courier_id,
  a.status as assignment_status,
  o.delivery_window_start,
  o.delivery_window_end,
  o.requested_at,
  o.due_by
from core."order" o
left join billing.order_pricing op on op.order_id = o.id
left join ops.assignment a on a.order_id = o.id
order by o.requested_at desc;

-- =========================================
--  CIERRE DIARIO DESDE WEB (RPC)
-- =========================================
create or replace function billing.fn_close_daily_settlement(
  p_merchant_id uuid,
  p_day date,
  p_mode text default 'auto',          -- 'csv' | 'auto'
  p_created_by uuid default auth.uid(),
  p_notes text default null
) returns uuid
language plpgsql
as
$$
declare
  v_settlement_id uuid;
begin
  -- upsert del settlement diario (idempotente por merchant+día)
  insert into billing.settlement (id, merchant_id, period_start, period_end, status, run_source, created_by_auth, notes)
  values (gen_random_uuid(), p_merchant_id, p_day, p_day, 'open', 'web', p_created_by, p_notes)
  on conflict (merchant_id, period_start, period_end)
  where excluded.period_start = excluded.period_end
  do update set notes = coalesce(excluded.notes, billing.settlement.notes)
  returning id into v_settlement_id;

  -- Candidatos: pedidos del día que estén entregados O rechazados en puerta, no liquidados aún
  with eligible_orders as (
    select
      o.id as order_id,
      o.merchant_id,
      o.requested_at::date as requested_date,
      o.delivery_status,
      coalesce(op.base_amount_gs, 0) as delivery_tariff,
      coalesce(
        (select sum(amount_gs) from billing.collection c where c.order_id = o.id and c.status = 'paid'),
        0
      ) as total_collected
    from core."order" o
    left join billing.order_pricing op on op.order_id = o.id
    where o.merchant_id = p_merchant_id
      and o.requested_at::date = p_day
      and coalesce(o.settled_with_merchant, false) = false
      and o.delivery_status in ('entregado', 'rechazado_puerta')
  )
  insert into billing.settlement_item (settlement_id, order_id, amount_gs)
  select
    v_settlement_id,
    e.order_id,
    case p_mode
      when 'csv' then 0 -- si vas a cargar desde staging; luego editás el item
      when 'auto' then
        case e.delivery_status
          -- Entregado: comercio recibe (cobrado - tarifa)
          when 'entregado' then greatest(e.total_collected - e.delivery_tariff, 0)
          -- Rechazado en puerta: comercio debe pagar la tarifa (valor negativo)
          when 'rechazado_puerta' then -e.delivery_tariff
          else 0
        end
      else 0
    end::int
  from eligible_orders e
  on conflict do nothing; -- protegido además por uq_settlement_item_order

  -- actualizar agregados del settlement
  update billing.settlement s
     set total_orders = (select count(*) from billing.settlement_item si where si.settlement_id = s.id),
         total_gs     = (select coalesce(sum(amount_gs),0) from billing.settlement_item si where si.settlement_id = s.id)
   where s.id = v_settlement_id;

  -- marcar pedidos como rendidos con el negocio
  update core."order" o
     set settled_with_merchant = true
   where o.id in (select order_id from billing.settlement_item where settlement_id = v_settlement_id);

  return v_settlement_id;
end;
$$;

-- =========================================
--  ÍNDICES CLAVE
-- =========================================
create index if not exists ix_order_merchant_time on core."order"(merchant_id, requested_at desc);
create index if not exists ix_order_status on core."order"(status);
create index if not exists ix_order_scheduled_date on core."order"(scheduled_date) where scheduled_date is not null;
create index if not exists ix_assignment_order on ops.assignment(order_id);
create index if not exists ix_assignment_courier_status on ops.assignment(courier_id, status);
create index if not exists ix_collection_order_status on billing.collection(order_id, status);
create index if not exists ix_settlement_period on billing.settlement(merchant_id, period_start, period_end);

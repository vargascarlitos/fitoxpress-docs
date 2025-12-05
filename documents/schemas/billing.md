# Esquema `billing` - Facturación

Este esquema gestiona todo lo relacionado con dinero: pricing de pedidos, cobros contra-entrega, liquidaciones a comercios y tarifas personalizadas.

---

## Diagrama ER

```mermaid
erDiagram
    order ||--|| order_pricing : "tiene precio"
    order ||--o{ collection : "tiene cobros"
    
    merchant ||--o{ settlement : "tiene liquidaciones"
    merchant ||--o{ merchant_city_rate : "tiene tarifas custom"
    merchant ||--o{ merchant_zone_rate : "tiene tarifas custom"
    
    settlement ||--o{ settlement_item : "contiene"
    settlement_item }o--|| order : "de"
    
    order_pricing }o--o| city : "ciudad destino"
    order_pricing }o--o| zone : "zona destino"
    merchant_city_rate }o--|| city : "para ciudad"
    merchant_zone_rate }o--|| zone : "para zona"

    order_pricing {
        uuid order_id PK_FK
        bigint city_id FK
        bigint zone_id FK
        integer base_amount_gs
        integer extras_gs
        integer total_amount_gs "GENERATED"
    }

    collection {
        uuid id PK
        uuid order_id FK
        payment_method method
        payment_status status
        integer amount_gs
        timestamptz occurred_at
        text notes
    }

    settlement {
        uuid id PK
        uuid merchant_id FK
        date period_start
        date period_end
        settlement_status status
        integer total_orders
        bigint total_gs
        text run_source
        uuid created_by_auth
        text notes
        timestamptz created_at
    }

    settlement_item {
        bigserial id PK
        uuid settlement_id FK
        uuid order_id FK
        integer amount_gs
    }

    merchant_city_rate {
        bigserial id PK
        uuid merchant_id FK
        bigint city_id FK
        integer amount_gs
        date effective_from
        date effective_to
    }

    merchant_zone_rate {
        bigserial id PK
        uuid merchant_id FK
        bigint zone_id FK
        integer amount_gs
        date effective_from
        date effective_to
    }
```

---

## Tablas

### `billing.order_pricing`

Pricing calculado para cada pedido (tarifa de envío).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `order_id` | `uuid` | NO | - | PK y FK a `core.order` |
| `city_id` | `bigint` | SÍ | - | FK a `ref.city` (destino) |
| `zone_id` | `bigint` | SÍ | - | FK a `ref.zone` (destino) |
| `base_amount_gs` | `integer` | SÍ | - | Tarifa base (debe ser >= 0) |
| `extras_gs` | `integer` | NO | `0` | Cargos adicionales |
| `total_amount_gs` | `integer` | NO | GENERATED | `base_amount_gs + extras_gs` |

**Constraints:**
- `PRIMARY KEY (order_id)`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`
- `FOREIGN KEY (city_id) REFERENCES ref.city(id)`
- `FOREIGN KEY (zone_id) REFERENCES ref.zone(id)`
- `CHECK (base_amount_gs >= 0)`

**Trigger:**
- `trg_fill_order_pricing`: Al insertar, si `base_amount_gs` es null o 0, calcula automáticamente usando `fn_resolve_rate_v2()`

**Cálculo automático de tarifa:**
1. Si el comercio tiene `tariff_mode = 'custom'`:
   - Busca primero en `merchant_zone_rate` (si hay zona)
   - Luego en `merchant_city_rate`
   - Si no encuentra y `allow_tariff_fallback = true`, va al estándar
2. Si es `tariff_mode = 'standard'` o fallback:
   - Busca en `ref.zone_rate` (si hay zona)
   - Luego en `ref.city_rate`

---

### `billing.collection`

Cobros realizados al destinatario (contra-entrega).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `order_id` | `uuid` | NO | - | FK a `core.order` |
| `method` | `payment_method` | NO | - | Método de pago |
| `status` | `payment_status` | NO | `'pending'` | Estado del cobro |
| `amount_gs` | `integer` | NO | - | Monto cobrado (>= 0) |
| `occurred_at` | `timestamptz` | NO | `now()` | Fecha/hora del cobro |
| `notes` | `text` | SÍ | - | Notas adicionales |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`
- `CHECK (amount_gs >= 0)`

**Índices:**
- `ix_collection_order_status` en `(order_id, status)`

**Métodos de pago (`payment_method`):**

| Valor | Descripción |
|-------|-------------|
| `cash` | Efectivo |
| `pos` | POS/tarjeta de débito o crédito |
| `transfer` | Transferencia bancaria |
| `gateway` | Pasarela de pago online |

**Estados (`payment_status`):**

| Valor | Descripción |
|-------|-------------|
| `pending` | Cobro pendiente |
| `paid` | Cobro completado |
| `failed` | Cobro fallido |
| `refunded` | Reembolsado |

**Trigger:**
- `trg_collection_mark_cobrado`: Cuando `status` cambia a `'paid'`, actualiza automáticamente `cash_status = 'cobrado'` en el pedido.

---

### `billing.settlement`

Liquidaciones a comercios (resumen de lo que se le debe pagar o cobrar).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `period_start` | `date` | NO | - | Inicio del período |
| `period_end` | `date` | NO | - | Fin del período |
| `status` | `settlement_status` | NO | `'open'` | Estado de la liquidación |
| `total_orders` | `integer` | NO | `0` | Cantidad de pedidos |
| `total_gs` | `bigint` | NO | `0` | Total en guaraníes |
| `run_source` | `text` | SÍ | - | Origen (ej: 'web', 'csv') |
| `created_by_auth` | `uuid` | SÍ | - | Usuario que creó |
| `notes` | `text` | SÍ | - | Notas adicionales |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`
- `UNIQUE (merchant_id, period_start, period_end) WHERE period_start = period_end` - Solo una liquidación diaria por comercio

**Índices:**
- `ix_settlement_period` en `(merchant_id, period_start, period_end)`

**Estados (`settlement_status`):**

| Valor | Descripción |
|-------|-------------|
| `open` | Liquidación abierta/en proceso |
| `paid` | Pagada al comercio |
| `canceled` | Cancelada |

---

### `billing.settlement_item`

Detalle de cada pedido incluido en una liquidación.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `settlement_id` | `uuid` | NO | - | FK a `billing.settlement` |
| `order_id` | `uuid` | NO | - | FK a `core.order` |
| `amount_gs` | `integer` | NO | - | Monto para este pedido |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (settlement_id) REFERENCES billing.settlement(id) ON DELETE CASCADE`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE RESTRICT`
- `UNIQUE (order_id)` - Un pedido solo puede estar en una liquidación

**Cálculo del monto:**
```
amount_gs = cobrado_al_cliente - tarifa_envio
```

Es decir, lo que el comercio debe recibir después de descontar el costo de envío.

---

### `billing.merchant_city_rate`

Tarifas personalizadas por ciudad para un comercio específico.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `city_id` | `bigint` | NO | - | FK a `ref.city` |
| `amount_gs` | `integer` | NO | - | Tarifa en guaraníes (> 0) |
| `effective_from` | `date` | NO | `current_date` | Fecha inicio vigencia |
| `effective_to` | `date` | SÍ | - | Fecha fin vigencia (null = vigente) |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`
- `FOREIGN KEY (city_id) REFERENCES ref.city(id) ON DELETE CASCADE`
- `UNIQUE (merchant_id, city_id, effective_from)` - Una tarifa por ciudad por fecha
- `CHECK (amount_gs > 0)`

**Ejemplo:**
Un comercio grande con contrato especial puede tener:
- Asunción: 25.000 Gs (estándar es 30.000 Gs)
- Lambaré: 25.000 Gs (estándar es 30.000 Gs)

---

### `billing.merchant_zone_rate`

Tarifas personalizadas por zona para un comercio específico.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `zone_id` | `bigint` | NO | - | FK a `ref.zone` |
| `amount_gs` | `integer` | NO | - | Tarifa en guaraníes (> 0) |
| `effective_from` | `date` | NO | `current_date` | Fecha inicio vigencia |
| `effective_to` | `date` | SÍ | - | Fecha fin vigencia (null = vigente) |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`
- `FOREIGN KEY (zone_id) REFERENCES ref.zone(id) ON DELETE CASCADE`
- `UNIQUE (merchant_id, zone_id, effective_from)` - Una tarifa por zona por fecha
- `CHECK (amount_gs > 0)`

---

## Funciones

### `billing.fn_resolve_rate_v2(p_merchant_id, p_city_id, p_zone_id, p_at_date)`

Resuelve la tarifa aplicable para un pedido según el comercio y destino.

**Parámetros:**
| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `p_merchant_id` | `uuid` | - | ID del comercio |
| `p_city_id` | `bigint` | - | ID de la ciudad destino |
| `p_zone_id` | `bigint` | `null` | ID de la zona destino (opcional) |
| `p_at_date` | `date` | `current_date` | Fecha para validar vigencia |

**Retorna:** `TABLE (source text, amount_gs integer, city_id bigint, zone_id bigint)`

**Valores de `source`:**

| Valor | Significado |
|-------|-------------|
| `custom_zone` | Tarifa custom del comercio por zona |
| `custom_city` | Tarifa custom del comercio por ciudad |
| `standard_zone` | Tarifa estándar por zona |
| `standard_city` | Tarifa estándar por ciudad |
| `not_found` | No se encontró tarifa aplicable |

**Lógica de prioridad:**
```
1. Si merchant.tariff_mode = 'custom':
   a. Buscar merchant_zone_rate (si hay zona)
   b. Buscar merchant_city_rate
   c. Si allow_tariff_fallback = true, ir a estándar
   d. Si no, retornar 'not_found'

2. Estándar:
   a. Buscar zone_rate (si hay zona)
   b. Buscar city_rate
   c. Retornar 'not_found' si no hay
```

---

### `billing.fn_clone_standard_rates(p_merchant_id, p_effective_from, p_replace_existing)`

Clona las tarifas estándar actuales como tarifas custom para un comercio.

**Parámetros:**
| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `p_merchant_id` | `uuid` | - | ID del comercio |
| `p_effective_from` | `date` | `current_date` | Fecha de inicio |
| `p_replace_existing` | `boolean` | `true` | Reemplazar tarifas existentes |

**Retorna:** `TABLE (cloned_city_count integer, cloned_zone_count integer)`

**Uso típico:**
Cuando un comercio pasa de tarifario estándar a custom, se clonan todas las tarifas estándar como punto de partida y luego se ajustan las que correspondan.

---

### `billing.fn_enable_custom_with_clone(p_merchant_id, p_effective_from, p_replace_existing, p_allow_fallback)`

Habilita tarifario custom para un comercio y clona las tarifas estándar.

**Parámetros:**
| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `p_merchant_id` | `uuid` | - | ID del comercio |
| `p_effective_from` | `date` | `current_date` | Fecha de inicio |
| `p_replace_existing` | `boolean` | `true` | Reemplazar tarifas existentes |
| `p_allow_fallback` | `boolean` | `true` | Permitir fallback a estándar |

**Acciones:**
1. Actualiza `merchant.tariff_mode = 'custom'`
2. Actualiza `merchant.allow_tariff_fallback`
3. Llama a `fn_clone_standard_rates()`

---

### `billing.fn_close_daily_settlement(p_merchant_id, p_day, p_mode, p_created_by, p_notes)`

Cierra la liquidación diaria de un comercio.

**Parámetros:**
| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `p_merchant_id` | `uuid` | - | ID del comercio |
| `p_day` | `date` | - | Día a liquidar |
| `p_mode` | `text` | `'auto'` | Modo: 'auto' o 'csv' |
| `p_created_by` | `uuid` | `auth.uid()` | Usuario que ejecuta |
| `p_notes` | `text` | `null` | Notas |

**Retorna:** `uuid` - ID del settlement creado

**Modos:**
- `'auto'`: Calcula automáticamente según el estado del pedido
- `'csv'`: Crea items con monto 0, para cargar desde staging después

**Lógica de cálculo (modo 'auto'):**

| Estado del Pedido | Cálculo | Resultado |
|-------------------|---------|-----------|
| `entregado` | `cobrado - tarifa_delivery` | Comercio recibe (valor positivo) |
| `rechazado_puerta` | `-tarifa_delivery` | Comercio debe (valor negativo) |

**Ejemplo de cierre:**

| Pedido | Estado | Cobrado | Tarifa | amount_gs |
|--------|--------|---------|--------|-----------|
| #1 | entregado | 185.000 | 25.000 | +160.000 |
| #2 | entregado | 200.000 | 30.000 | +170.000 |
| #3 | rechazado_puerta | 0 | 25.000 | -25.000 |
| **Total** | | | | **+305.000** |

**Flujo:**
1. Crea o actualiza el `settlement` para el comercio y día
2. Busca pedidos `entregado` o `rechazado_puerta` ese día que no estén liquidados
3. Crea `settlement_item` para cada pedido con el cálculo correspondiente
4. Actualiza totales del settlement (puede ser negativo si hay muchos rechazos)
5. Marca `settled_with_merchant = true` en los pedidos

---

## Vistas

### `billing.v_current_rates`

Vista de todas las tarifas estándar vigentes.

| Columna | Descripción |
|---------|-------------|
| `source` | 'standard_city' o 'standard_zone' |
| `merchant_id` | Siempre null (es estándar) |
| `city_id` | ID de la ciudad |
| `zone_id` | ID de la zona (null si es tarifa por ciudad) |
| `city_name` | Nombre de la ciudad |
| `zone_name` | Nombre de la zona |
| `amount_gs` | Tarifa vigente |

**Uso:**
```sql
-- Ver todas las tarifas estándar actuales
SELECT * FROM billing.v_current_rates;

-- Ver tarifas por ciudad
SELECT city_name, amount_gs 
FROM billing.v_current_rates 
WHERE source = 'standard_city';
```

---

## Notas para Desarrolladores

### Proceso de cierre diario

```
1. Admin/Operador ejecuta cierre para un comercio y fecha
2. Sistema busca pedidos: delivery_status IN ('entregado', 'rechazado_puerta') AND settled_with_merchant=false
3. Por cada pedido:
   - Si entregado: amount_gs = cobrado - tarifa (positivo, comercio recibe)
   - Si rechazado_puerta: amount_gs = -tarifa (negativo, comercio debe)
   - Crea settlement_item
4. Suma totales en settlement (puede ser negativo si hay muchos rechazos)
5. Marca pedidos como settled_with_merchant=true
6. Settlement queda en status='open' hasta que se pague
7. Cuando se paga al comercio (o comercio paga si es negativo), status='paid'
```

### Fórmula de liquidación

**Pedido entregado:**
```
Lo que recibe el comercio = Cobrado al cliente - Tarifa de envío

Ejemplo:
- Cobro al cliente: 185.000 Gs
- Tarifa de envío: 25.000 Gs
- El comercio recibe: +160.000 Gs
```

**Pedido rechazado en puerta:**
```
Lo que debe el comercio = Tarifa de envío (el rider hizo el viaje)

Ejemplo:
- Cobro al cliente: 0 Gs (no se cobró)
- Tarifa de envío: 25.000 Gs
- El comercio debe: -25.000 Gs
```

**Total del cierre:**
```
Total = Σ(entregas) - Σ(rechazos)

Ejemplo con 3 pedidos:
- Pedido 1 (entregado): +160.000
- Pedido 2 (entregado): +170.000
- Pedido 3 (rechazado): -25.000
- Total: +305.000 Gs (comercio recibe)
```

### Tarifario custom vs estándar

| Configuración | Comportamiento |
|---------------|----------------|
| `standard` + cualquier fallback | Usa solo tarifas de `ref.*_rate` |
| `custom` + `fallback=true` | Busca en custom, si no hay usa estándar |
| `custom` + `fallback=false` | Solo usa custom, si no hay queda en 0 |


# Esquema `core` - Entidades Principales

Este esquema contiene las entidades principales del negocio: usuarios, comercios, direcciones, contactos, destinatarios, productos y pedidos.

---

## Diagrama ER

```mermaid
erDiagram
    user_profile ||--o| merchant : "puede ser dueño"
    merchant ||--o{ merchant_address : "tiene"
    merchant ||--o{ product : "vende"
    merchant ||--o{ order : "genera"
    
    address ||--o{ merchant_address : "asignada a"
    contact ||--o{ recipient : "tiene"
    recipient ||--o{ order : "recibe"
    address ||--o| recipient : "dirección default"
    
    order ||--o{ order_item : "contiene"
    order ||--o{ order_event : "tiene historial"
    order ||--o| order_pod : "tiene POD"
    order }o--|| address : "pickup"
    order }o--|| address : "dropoff"
    
    product ||--o{ order_item : "en"

    user_profile {
        uuid auth_user_id PK
        app_role role
        text full_name
        text phone
        timestamptz created_at
        boolean is_active
        boolean password_change_required
    }

    merchant {
        uuid id PK
        text name
        text ruc
        text phone
        text email
        uuid auth_user_id FK
        merchant_tariff_mode tariff_mode
        boolean allow_tariff_fallback
        boolean is_active
        timestamptz created_at
    }

    address {
        uuid id PK
        text label
        text street
        text number
        text neighborhood
        bigint city_id FK
        bigint zone_id FK
        text reference_notes
        geometry location
        timestamptz created_at
    }

    contact {
        uuid id PK
        text full_name
        text phone
        text email
    }

    recipient {
        uuid id PK
        uuid contact_id FK
        uuid default_address FK
        timestamptz created_at
    }

    product {
        uuid id PK
        uuid merchant_id FK
        text name
        text sku
        integer unit_price_gs
        boolean is_active
    }

    order {
        uuid id PK
        uuid merchant_id FK
        text external_ref
        uuid recipient_id FK
        uuid pickup_address_id FK
        uuid dropoff_address_id FK
        integer declared_value_gs
        integer cash_to_collect_gs
        text notes
        order_status status
        delivery_status delivery_status
        cash_status cash_status
        boolean settled_with_merchant
        boolean settled_with_rider
        timestamptz delivery_window_start
        timestamptz delivery_window_end
        timestamptz requested_at
        timestamptz due_by
        uuid created_by_auth
        timestamptz updated_at
    }

    order_item {
        bigserial id PK
        uuid order_id FK
        uuid product_id FK
        text description
        integer qty
        integer unit_price_gs
    }

    order_event {
        bigserial id PK
        uuid order_id FK
        timestamptz at
        order_status from_status
        order_status to_status
        uuid actor_auth
        text notes
    }

    order_pod {
        uuid order_id PK_FK
        timestamptz delivered_at
        text receiver_name
        text signature_url
        text photo_url
        text notes
    }
```

---

## Tablas

### `core.user_profile`

Perfil de usuario vinculado a `auth.users` de Supabase.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `auth_user_id` | `uuid` | NO | - | PK, referencia a `auth.users.id` |
| `role` | `app_role` | NO | - | Rol del usuario (admin/operator/merchant/rider) |
| `full_name` | `text` | SÍ | - | Nombre completo |
| `phone` | `text` | SÍ | - | Teléfono de contacto |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |
| `is_active` | `boolean` | NO | `true` | Si el usuario está activo |
| `password_change_required` | `boolean` | NO | `false` | Si requiere cambio de contraseña al siguiente login |

**Constraints:**
- `PRIMARY KEY (auth_user_id)`

**Notas:**
- El `auth_user_id` viene de la autenticación de Supabase
- Un usuario puede ser merchant o rider, vinculado a sus respectivas tablas
- El campo `is_active` permite desactivar usuarios sin eliminarlos
- El campo `password_change_required` fuerza al usuario a cambiar contraseña

---

### `core.merchant`

Comercios/tiendas que generan pedidos.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `name` | `text` | NO | - | Nombre del comercio |
| `ruc` | `text` | SÍ | - | RUC (identificación fiscal) |
| `phone` | `text` | SÍ | - | Teléfono del comercio |
| `email` | `text` | SÍ | - | Email de contacto |
| `auth_user_id` | `uuid` | SÍ | - | Usuario dueño del comercio |
| `tariff_mode` | `merchant_tariff_mode` | NO | `'standard'` | Modo de tarifario |
| `allow_tariff_fallback` | `boolean` | NO | `true` | Permitir fallback a tarifa estándar |
| `is_active` | `boolean` | NO | `true` | Si el comercio está activo |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |

**Constraints:**
- `PRIMARY KEY (id)`

**Modos de tarifario:**
- `standard`: Usa las tarifas de `ref.city_rate` y `ref.zone_rate`
- `custom`: Usa tarifas personalizadas de `billing.merchant_city_rate` y `billing.merchant_zone_rate`

**Fallback:**
- Si `allow_tariff_fallback = true` y no se encuentra tarifa custom, usa la estándar
- Si `allow_tariff_fallback = false` y no hay tarifa custom, el precio queda en 0

---

### `core.address`

Direcciones reutilizables (pickup y dropoff).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `label` | `text` | SÍ | - | Etiqueta (ej: "Sucursal Centro") |
| `street` | `text` | SÍ | - | Calle |
| `number` | `text` | SÍ | - | Número de casa |
| `neighborhood` | `text` | SÍ | - | Barrio |
| `city_id` | `bigint` | SÍ | - | FK a `ref.city` |
| `zone_id` | `bigint` | SÍ | - | FK a `ref.zone` |
| `reference_notes` | `text` | SÍ | - | Referencias adicionales |
| `location` | `geometry(Point,4326)` | SÍ | - | Coordenadas GPS (PostGIS) |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (city_id) REFERENCES ref.city(id)`
- `FOREIGN KEY (zone_id) REFERENCES ref.zone(id)`

**Notas:**
- El campo `location` almacena coordenadas en formato WGS84 (SRID 4326)
- Se usa para determinar automáticamente la tarifa basada en ubicación

---

### `core.contact`

Datos de contacto de personas (pueden ser reutilizados).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `full_name` | `text` | NO | - | Nombre completo |
| `phone` | `text` | SÍ | - | Teléfono |
| `email` | `text` | SÍ | - | Email |

**Constraints:**
- `PRIMARY KEY (id)`

---

### `core.merchant_address`

Relación N:M entre comercios y direcciones (sucursales del comercio).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `address_id` | `uuid` | NO | - | FK a `core.address` |
| `is_default` | `boolean` | NO | `false` | Si es la dirección principal |

**Constraints:**
- `PRIMARY KEY (merchant_id, address_id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`
- `FOREIGN KEY (address_id) REFERENCES core.address(id) ON DELETE RESTRICT`
- `UNIQUE (merchant_id) WHERE is_default = true` - Solo una dirección por defecto

---

### `core.recipient`

Destinatarios de los pedidos.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `contact_id` | `uuid` | NO | - | FK a `core.contact` |
| `default_address` | `uuid` | SÍ | - | FK a `core.address` |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (contact_id) REFERENCES core.contact(id) ON DELETE RESTRICT`
- `FOREIGN KEY (default_address) REFERENCES core.address(id)`

---

### `core.product`

Productos del catálogo de cada comercio.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `name` | `text` | NO | - | Nombre del producto |
| `sku` | `text` | SÍ | - | Código SKU |
| `unit_price_gs` | `integer` | SÍ | - | Precio unitario en guaraníes |
| `is_active` | `boolean` | NO | `true` | Si el producto está activo |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`
- `UNIQUE (merchant_id, coalesce(sku,''), name)` - SKU+nombre únicos por comercio

---

### `core.order`

Pedidos de entrega.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `external_ref` | `text` | SÍ | - | Referencia externa del comercio |
| `recipient_id` | `uuid` | NO | - | FK a `core.recipient` |
| `pickup_address_id` | `uuid` | NO | - | FK dirección de recogida |
| `dropoff_address_id` | `uuid` | NO | - | FK dirección de entrega |
| `declared_value_gs` | `integer` | SÍ | `0` | Valor declarado del paquete |
| `cash_to_collect_gs` | `integer` | SÍ | `0` | Monto a cobrar contra-entrega |
| `notes` | `text` | SÍ | - | Notas adicionales |
| `status` | `order_status` | NO | `'created'` | Estado legacy |
| `delivery_status` | `delivery_status` | NO | `'recepcionado'` | Estado de entrega operativo |
| `cash_status` | `cash_status` | NO | `'sin_cobro'` | Estado del cobro |
| `settled_with_merchant` | `boolean` | NO | `false` | Rendido con el comercio |
| `settled_with_rider` | `boolean` | NO | `false` | Rendido con el rider |
| `delivery_window_start` | `timestamptz` | SÍ | - | Inicio ventana de entrega |
| `delivery_window_end` | `timestamptz` | SÍ | - | Fin ventana de entrega |
| `requested_at` | `timestamptz` | NO | `now()` | Fecha de solicitud |
| `due_by` | `timestamptz` | SÍ | - | Fecha límite de entrega |
| `created_by_auth` | `uuid` | SÍ | - | Usuario que creó el pedido |
| `updated_at` | `timestamptz` | NO | `now()` | Última actualización |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE RESTRICT`
- `FOREIGN KEY (recipient_id) REFERENCES core.recipient(id) ON DELETE RESTRICT`
- `FOREIGN KEY (pickup_address_id) REFERENCES core.address(id)`
- `FOREIGN KEY (dropoff_address_id) REFERENCES core.address(id)`

**Índices:**
- `ix_order_merchant_time` en `(merchant_id, requested_at DESC)`
- `ix_order_status` en `(status)`

**Estados operativos:**

| delivery_status | cash_status | Descripción |
|-----------------|-------------|-------------|
| `recepcionado` | `sin_cobro` | Pedido recibido, pendiente |
| `en_transito` | `sin_cobro` | Rider en camino |
| `entregado` | `sin_cobro` | Entregado, sin cobro aún |
| `entregado` | `cobrado` | Entregado y cobrado |
| `rechazado_puerta` | `sin_cobro` | Cliente rechazó en destino (se cobra tarifa al comercio) |

**Flags de liquidación:**
- `settled_with_merchant`: Se incluyó en una liquidación al comercio
- `settled_with_rider`: Se pagó al rider por esta entrega

---

### `core.order_item`

Ítems/productos dentro de un pedido.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `order_id` | `uuid` | NO | - | FK a `core.order` |
| `product_id` | `uuid` | SÍ | - | FK a `core.product` (opcional) |
| `description` | `text` | NO | - | Descripción del ítem |
| `qty` | `integer` | NO | - | Cantidad (debe ser > 0) |
| `unit_price_gs` | `integer` | SÍ | `0` | Precio unitario |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`
- `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- `CHECK (qty > 0)`

---

### `core.order_event`

Historial de cambios de estado del pedido.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `order_id` | `uuid` | NO | - | FK a `core.order` |
| `at` | `timestamptz` | NO | `now()` | Timestamp del evento |
| `from_status` | `order_status` | SÍ | - | Estado anterior |
| `to_status` | `order_status` | NO | - | Estado nuevo |
| `actor_auth` | `uuid` | SÍ | - | Usuario que realizó el cambio |
| `notes` | `text` | SÍ | - | Notas del evento |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`

---

### `core.order_pod`

Prueba de entrega (Proof of Delivery).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `order_id` | `uuid` | NO | - | PK y FK a `core.order` |
| `delivered_at` | `timestamptz` | SÍ | - | Fecha/hora de entrega |
| `receiver_name` | `text` | SÍ | - | Nombre de quien recibió |
| `signature_url` | `text` | SÍ | - | URL de la firma digital |
| `photo_url` | `text` | SÍ | - | URL de foto del paquete entregado |
| `notes` | `text` | SÍ | - | Notas de la entrega |

**Constraints:**
- `PRIMARY KEY (order_id)`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`

---

## Notas para Desarrolladores

### Crear un pedido desde mensaje WhatsApp

1. El mensaje llega a `ingest.message`
2. Se parsea y crea `ingest.order_intent`
3. Si el parsing es exitoso, se crea:
   - `core.contact` (si no existe)
   - `core.recipient` (si no existe)
   - `core.address` (dirección de entrega)
   - `core.order` con referencia al recipient y direcciones
   - `billing.order_pricing` (trigger calcula la tarifa)

### Ciclo de vida del pedido

```
                              ┌─→ entregado
                              │        ↓
recepcionado → en_transito ───┤   cash_status: cobrado
                              │        ↓
                              └─→ rechazado_puerta
                                       ↓
                              settled_with_merchant: true
                                       ↓
                              settled_with_rider: true
```

**Nota sobre rechazos:**
- Cuando el cliente rechaza en la puerta, el rider marca `rechazado_puerta`
- El pedido NO tiene cobro (`cash_status` queda `sin_cobro`)
- En el cierre diario, se cobra la tarifa de envío al comercio (el rider hizo el viaje)

### Ventanas de entrega

Los campos `delivery_window_start` y `delivery_window_end` permiten especificar un horario de entrega preferido, como "antes de las 12 hs".


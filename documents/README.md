# FitoxPress - Documentación de Base de Datos

Sistema de gestión de logística y delivery para comercios en Paraguay. La base de datos está implementada en **Supabase (PostgreSQL)**.

## Descripción General

FitoxPress es una plataforma que permite:

- **Recepción de pedidos** vía WhatsApp mediante un bot que parsea mensajes
- **Gestión de comercios** con tarifarios estándar o personalizados
- **Asignación de riders** por zona/ciudad
- **Seguimiento de entregas** con estados operativos
- **Liquidaciones** tanto con comercios como con riders
- **Cobros en destino** (contra-entrega)

---

## Arquitectura de Esquemas

La base de datos está organizada en 6 esquemas lógicos:

| Esquema | Descripción | Documentación |
|---------|-------------|---------------|
| `ref` | Datos de referencia: ciudades, zonas y tarifas estándar | [ref.md](schemas/ref.md) |
| `core` | Entidades principales: usuarios, comercios, pedidos | [core.md](schemas/core.md) |
| `ops` | Operaciones: riders, asignaciones, tracking | [ops.md](schemas/ops.md) |
| `billing` | Facturación: cobros, liquidaciones, tarifas custom | [billing.md](schemas/billing.md) |
| `ingest` | Ingesta: mensajes WhatsApp, parsing automático | [ingest.md](schemas/ingest.md) |
| `audit` | Auditoría: registro de eventos del sistema | [audit.md](schemas/audit.md) |

Ver el [Diagrama ER completo](diagrams/er-diagram.md) para una vista general de las relaciones.

---

## Tipos de Usuario

El sistema maneja 4 roles definidos en el enum `app_role`:

| Rol | Descripción |
|-----|-------------|
| `admin` | Acceso total al sistema. Puede realizar liquidaciones con riders. |
| `operator` | Gestiona pedidos, asigna riders, realiza cobros. |
| `merchant` | Comercio/tienda. Ve sus propios pedidos y liquidaciones. |
| `rider` | Repartidor. Ve sus asignaciones y entregas. |

---

## Enums Globales

### `merchant_tariff_mode`
Modo de tarifario del comercio.

| Valor | Descripción |
|-------|-------------|
| `standard` | Usa el tarifario estándar por ciudad/zona |
| `custom` | Tiene tarifas personalizadas definidas |

### `app_role`
Roles de usuario en la aplicación.

| Valor | Descripción |
|-------|-------------|
| `admin` | Administrador del sistema |
| `operator` | Operador de logística |
| `merchant` | Comercio/tienda |
| `rider` | Repartidor |

### `delivery_status`
Estado de entrega del pedido (operativo).

| Valor | Descripción |
|-------|-------------|
| `recepcionado` | Pedido recibido, pendiente de asignar |
| `en_transito` | Rider en camino a entregar |
| `entregado` | Entrega completada |
| `rechazado_puerta` | Cliente rechazó el pedido en destino |
| `reagendado` | Cliente pidió entregar otro día |

### `cash_status`
Estado del cobro contra-entrega.

| Valor | Descripción |
|-------|-------------|
| `sin_cobro` | Pendiente de cobrar |
| `cobrado` | Dinero cobrado al destinatario |

### `order_status` (legacy)
Estados detallados del pedido (mantenido por compatibilidad).

| Valor | Descripción |
|-------|-------------|
| `draft` | Borrador |
| `created` | Creado |
| `assigned` | Asignado a rider |
| `picked_up` | Recogido del comercio |
| `en_route` | En ruta de entrega |
| `delivered` | Entregado |
| `failed` | Entrega fallida |
| `canceled` | Cancelado |

### `vehicle_type` (esquema ops)
Tipo de vehículo del rider.

| Valor | Descripción |
|-------|-------------|
| `motorcycle` | Motocicleta |
| `car` | Automóvil |
| `bicycle` | Bicicleta |
| `on_foot` | A pie |

### `assignment_status` (esquema ops)
Estado de la asignación rider-pedido.

| Valor | Descripción |
|-------|-------------|
| `pending` | Pendiente de aceptar |
| `accepted` | Aceptado por el rider |
| `picked_up` | Recogido |
| `en_route` | En ruta |
| `delivered` | Entregado |
| `failed` | Fallido |
| `canceled` | Cancelado |

### `payment_method` (esquema billing)
Método de pago para cobros.

| Valor | Descripción |
|-------|-------------|
| `cash` | Efectivo |
| `pos` | POS/tarjeta |
| `transfer` | Transferencia bancaria |
| `gateway` | Pasarela de pago online |

### `payment_status` (esquema billing)
Estado del pago/cobro.

| Valor | Descripción |
|-------|-------------|
| `pending` | Pendiente |
| `paid` | Pagado |
| `failed` | Fallido |
| `refunded` | Reembolsado |

### `settlement_status` (esquema billing)
Estado de la liquidación.

| Valor | Descripción |
|-------|-------------|
| `open` | Abierta/en proceso |
| `paid` | Pagada al comercio |
| `canceled` | Cancelada |

### `media_type` (esquema ingest)
Tipo de media en mensajes WhatsApp.

| Valor | Descripción |
|-------|-------------|
| `none` | Solo texto |
| `image` | Imagen |
| `audio` | Audio |
| `video` | Video |
| `document` | Documento |
| `location` | Ubicación GPS |

### `parse_status` (esquema ingest)
Estado del parsing de un mensaje.

| Valor | Descripción |
|-------|-------------|
| `pending` | Pendiente de procesar |
| `parsed` | Parseado exitosamente |
| `needs_review` | Requiere revisión manual |
| `rejected` | Rechazado |

---

## Extensiones PostgreSQL

El sistema utiliza las siguientes extensiones:

- **uuid-ossp**: Generación de UUIDs
- **pgcrypto**: Funciones criptográficas (gen_random_uuid)
- **postgis**: Datos geoespaciales (geometrías, coordenadas)

---

## Flujo General de un Pedido

```
1. INGESTA
   └── Mensaje WhatsApp → ingest.message → ingest.order_intent

2. CREACIÓN
   └── order_intent (parsed) → core.order + billing.order_pricing

3. ASIGNACIÓN
   └── core.order → ops.assignment (rider)

4. ENTREGA
   └── delivery_status: recepcionado → en_transito → entregado
                                                   → rechazado_puerta
                                                   → reagendado (scheduled_date)

5. COBRO (si entregado)
   └── billing.collection (cash_status: cobrado)

6. LIQUIDACIÓN
   └── billing.settlement (comercio) + ops.rider_payout (rider)
```

### Cierre diario

Solo se incluyen en el cierre:
- **entregado**: comercio recibe (cobrado - tarifa)
- **rechazado_puerta**: comercio paga (-tarifa)

NO se incluyen: `recepcionado`, `en_transito`, `reagendado`

---

## Navegación

- [Esquema ref - Referencia](schemas/ref.md)
- [Esquema core - Principal](schemas/core.md)
- [Esquema ops - Operaciones](schemas/ops.md)
- [Esquema billing - Facturación](schemas/billing.md)
- [Esquema ingest - Ingesta WhatsApp](schemas/ingest.md)
- [Esquema audit - Auditoría](schemas/audit.md)
- [Diagrama ER Completo](diagrams/er-diagram.md)


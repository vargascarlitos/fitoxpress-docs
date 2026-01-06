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

| Valor | Descripción | ¿Cobra tarifa? |
|-------|-------------|----------------|
| `recepcionado` | Pedido recibido, pendiente de asignar | - |
| `en_transito` | Rider en camino a entregar | - |
| `entregado` | Entrega completada | ✅ Sí |
| `rechazado_puerta` | Cliente rechazó el pedido en destino (rider llegó físicamente) | ✅ Sí |
| `cancelado_previo` | Cancelado antes de que el rider salga | ❌ No |
| `reagendado` | Cliente pidió entregar otro día | - |
| `no_atiende` | Cliente no atiende, se reagenda automáticamente al día siguiente | ❌ No |
| `para_devolucion` | Múltiples intentos fallidos, pedido para devolver al comercio | ❌ No |
| `extraviado` | Pedido perdido o extraviado | - |

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

### `rider_type` (esquema ops)
Tipo de contratación del rider.

| Valor | Descripción |
|-------|-------------|
| `fixed` | Rider fijo con sueldo mensual |
| `commission` | Rider comisionista (cobra % por entrega) |

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

### `bank_account_type` (esquema core)
Tipo de cuenta bancaria del comercio.

| Valor | Descripción |
|-------|-------------|
| `normal` | Cuenta bancaria tradicional (titular, banco, número) |
| `alias` | Cuenta por alias SIPAP (celular, correo, RUC, etc.) |

### `bank_alias_type` (esquema core)
Tipos de alias bancario según SIPAP Paraguay.

| Valor | Descripción |
|-------|-------------|
| `celular` | Número de celular |
| `correo` | Correo electrónico |
| `cedula_identidad` | Cédula de identidad |
| `ruc` | Registro Único de Contribuyente |
| `persona_fisica_no_residente` | Persona física no residente |
| `carnet_residencia` | Carnet de residencia permanente |

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
                                                   → no_atiende (reagenda auto)
                                                   → para_devolucion
                        recepcionado → cancelado_previo (antes de salir)

   └── Al pasar a entregado/rechazado_puerta:
       • Se llena automáticamente fecha_para_contabilidad = HOY
       • Se llena delivered_at en ops.assignment

5. COBRO (si entregado)
   └── billing.collection (cash_status: cobrado)

6. LIQUIDACIÓN COMERCIO
   └── billing.settlement (comercio) + billing.settlement_item

7. CIERRE DE CAJA DIARIO
   └── billing.get_daily_profit_report(fecha)
       • Filtra pedidos por fecha_para_contabilidad
       • Calcula ganancias por tipo de rider (fijo vs comisionista)
       • Resta gastos operativos y generales
```

### Cierre diario

Solo se incluyen en el cierre (generan tarifa):
- **entregado**: comercio recibe (cobrado - tarifa), empresa cobra tarifa
- **rechazado_puerta**: comercio paga (-tarifa), empresa cobra tarifa - el rider YA hizo el viaje

NO generan tarifa (no entran en cierre de caja):
- `recepcionado`, `en_transito`, `reagendado` - estados intermedios
- `cancelado_previo` - rider NO hizo el viaje
- `no_atiende` - se reagenda automáticamente
- `para_devolucion` - múltiples intentos fallidos

**Diferencia importante:**
- `rechazado_puerta`: El rider **llegó físicamente** al destino → se cobra tarifa al comercio
- `cancelado_previo`: El rider contactó al cliente **antes de salir** → NO se cobra tarifa
- `no_atiende`: Cliente no responde, pedido pasa al día siguiente → NO se cobra tarifa

**Campo clave para cierre:**
El campo `fecha_para_contabilidad` en `core.order` es la **fuente de verdad** para determinar en qué día se contabiliza el ingreso. Se llena automáticamente cuando el pedido pasa a `entregado` o `rechazado_puerta`.

---

## Documentación de Módulos

Guías técnicas para el desarrollo de cada módulo del sistema:

| Módulo | Descripción | Documentación |
|--------|-------------|---------------|
| **Pedidos** | Gestión y creación de pedidos, asignaciones | [pedidos.md](modulos/pedidos.md) |
| **Cierre de Caja** | Gestión financiera y cierre contable diario | [cierre-caja.md](modulos/cierre-caja.md) |

---

## Navegación

### Esquemas de Base de Datos
- [Esquema ref - Referencia](schemas/ref.md)
- [Esquema core - Principal](schemas/core.md)
- [Esquema ops - Operaciones](schemas/ops.md)
- [Esquema billing - Facturación](schemas/billing.md)
- [Esquema ingest - Ingesta WhatsApp](schemas/ingest.md)
- [Esquema audit - Auditoría](schemas/audit.md)

### Diagramas
- [Diagrama ER Completo](diagrams/er-diagram.md)

### Módulos de Desarrollo
- [Módulo de Pedidos](modulos/pedidos.md)
- [Módulo de Cierre de Caja](modulos/cierre-caja.md)


# Esquema `ingest` - Ingesta WhatsApp

Este esquema gestiona la recepción y parsing automático de mensajes de WhatsApp para crear pedidos.

---

## Diagrama ER

```mermaid
erDiagram
    channel ||--o{ channel_merchant : "conectado a"
    channel ||--o{ message : "recibe"
    channel_merchant }o--|| merchant : "comercio"
    
    message ||--o{ message_location : "tiene ubicaciones"
    message ||--o{ order_intent : "genera intents"
    
    order_intent }o--o| city : "ciudad detectada"
    order_intent ||--o| intent_order_link : "convertido a"
    intent_order_link }o--|| order : "pedido creado"

    channel {
        uuid id PK
        text provider
        text waba_id
        text phone_number
        text label
        boolean is_active
    }

    channel_merchant {
        uuid channel_id PK_FK
        uuid merchant_id PK_FK
        boolean is_default
    }

    message {
        uuid id PK
        uuid channel_id FK
        text wa_message_id
        text from_phone
        text to_phone
        timestamptz sent_at
        text raw_text
        media_type media_type
        text media_url
        jsonb payload_json
        text detected_lang
        timestamptz created_at
    }

    message_location {
        bigserial id PK
        uuid message_id FK
        double_precision lat
        double_precision lon
        text address_text
        double_precision accuracy_m
    }

    order_intent {
        uuid id PK
        uuid message_id FK
        parse_status status
        numeric confidence
        text recipient_name
        text recipient_phone
        text address_text
        bigint city_id FK
        geometry location
        text products_text
        integer amount_gs
        text notes
        timestamptz delivery_by
        timestamptz window_start
        timestamptz window_end
        jsonb errors
        timestamptz created_at
    }

    intent_order_link {
        uuid order_intent_id PK_FK
        uuid order_id FK
        timestamptz linked_at
        uuid linked_by_auth
    }
```

---

## Tablas

### `ingest.channel`

Canales de WhatsApp configurados para recibir mensajes.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `provider` | `text` | NO | `'whatsapp'` | Proveedor del canal |
| `waba_id` | `text` | SÍ | - | WhatsApp Business Account ID |
| `phone_number` | `text` | NO | - | Número de teléfono del canal |
| `label` | `text` | SÍ | - | Etiqueta descriptiva |
| `is_active` | `boolean` | NO | `true` | Si el canal está activo |

**Constraints:**
- `PRIMARY KEY (id)`
- `UNIQUE (phone_number)` - Un número por canal

**Ejemplo:**
```sql
INSERT INTO ingest.channel (phone_number, label)
VALUES ('+595981000000', 'Canal Principal FitoxPress');
```

---

### `ingest.channel_merchant`

Relación entre canales y comercios (qué comercio usa qué canal).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `channel_id` | `uuid` | NO | - | FK a `ingest.channel` |
| `merchant_id` | `uuid` | NO | - | FK a `core.merchant` |
| `is_default` | `boolean` | NO | `false` | Si es el comercio por defecto del canal |

**Constraints:**
- `PRIMARY KEY (channel_id, merchant_id)`
- `FOREIGN KEY (channel_id) REFERENCES ingest.channel(id) ON DELETE CASCADE`
- `FOREIGN KEY (merchant_id) REFERENCES core.merchant(id) ON DELETE CASCADE`

**Notas:**
- Un canal puede recibir pedidos de múltiples comercios
- Si hay un comercio "default", los mensajes sin identificación clara se asignan a ese comercio

---

### `ingest.message`

Mensajes de WhatsApp recibidos.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `channel_id` | `uuid` | SÍ | - | FK a `ingest.channel` |
| `wa_message_id` | `text` | SÍ | - | ID único del mensaje en WhatsApp |
| `from_phone` | `text` | NO | - | Número que envía |
| `to_phone` | `text` | SÍ | - | Número que recibe |
| `sent_at` | `timestamptz` | NO | `now()` | Fecha/hora del mensaje |
| `raw_text` | `text` | SÍ | - | Texto crudo del mensaje |
| `media_type` | `media_type` | NO | `'none'` | Tipo de media adjunta |
| `media_url` | `text` | SÍ | - | URL del archivo media |
| `payload_json` | `jsonb` | SÍ | - | Payload completo del webhook |
| `detected_lang` | `text` | SÍ | - | Idioma detectado |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de registro |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (channel_id) REFERENCES ingest.channel(id) ON DELETE SET NULL`
- `UNIQUE (wa_message_id)` - No duplicar mensajes

**Tipos de media (`media_type`):**

| Valor | Descripción |
|-------|-------------|
| `none` | Solo texto |
| `image` | Imagen adjunta |
| `audio` | Audio/nota de voz |
| `video` | Video |
| `document` | Documento (PDF, etc.) |
| `location` | Ubicación GPS compartida |

**Ejemplo de mensaje recibido:**
```
1- Nombre de quien recibe: Rosa Mersan
2-Telefono de contacto: +595981414003
3-Dirección de envío: Victor Boettner 210, Asunción
4-Productos: 1 x LINTERNA POTENTE CON ZOOM
5-Total a pagar: 185.000 PYG
6-Ubicación: [coordenadas]
```

---

### `ingest.message_location`

Ubicaciones GPS extraídas de mensajes (puede haber múltiples por mensaje).

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `bigserial` | NO | auto | Identificador único |
| `message_id` | `uuid` | NO | - | FK a `ingest.message` |
| `lat` | `double precision` | NO | - | Latitud |
| `lon` | `double precision` | NO | - | Longitud |
| `address_text` | `text` | SÍ | - | Dirección textual (si viene) |
| `accuracy_m` | `double precision` | SÍ | - | Precisión en metros |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (message_id) REFERENCES ingest.message(id) ON DELETE CASCADE`

**Índices:**
- `ix_msg_loc_message` en `(message_id)`

**Uso:**
La ubicación compartida en WhatsApp es clave para:
1. Determinar la ciudad/zona de destino
2. Calcular la tarifa de envío automáticamente
3. Facilitar la navegación del rider

---

### `ingest.order_intent`

Intención de pedido parseada desde un mensaje. Representa el resultado del parsing automático.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Identificador único |
| `message_id` | `uuid` | NO | - | FK a `ingest.message` |
| `status` | `parse_status` | NO | `'pending'` | Estado del parsing |
| `confidence` | `numeric(5,2)` | NO | `0.00` | Confianza del parsing (0-100) |
| `recipient_name` | `text` | SÍ | - | Nombre del destinatario |
| `recipient_phone` | `text` | SÍ | - | Teléfono del destinatario |
| `address_text` | `text` | SÍ | - | Dirección extraída |
| `city_id` | `bigint` | SÍ | - | FK a `ref.city` (detectada) |
| `location` | `geometry(Point,4326)` | SÍ | - | Coordenadas GPS |
| `products_text` | `text` | SÍ | - | Productos extraídos |
| `amount_gs` | `integer` | SÍ | - | Monto a cobrar extraído |
| `notes` | `text` | SÍ | - | Notas adicionales |
| `delivery_by` | `timestamptz` | SÍ | - | Fecha límite de entrega |
| `window_start` | `timestamptz` | SÍ | - | Inicio ventana de entrega |
| `window_end` | `timestamptz` | SÍ | - | Fin ventana de entrega |
| `errors` | `jsonb` | SÍ | - | Errores de parsing |
| `created_at` | `timestamptz` | NO | `now()` | Fecha de creación |

**Constraints:**
- `PRIMARY KEY (id)`
- `FOREIGN KEY (message_id) REFERENCES ingest.message(id) ON DELETE CASCADE`
- `FOREIGN KEY (city_id) REFERENCES ref.city(id)`

**Índices:**
- `ix_oi_status_conf` en `(status, confidence)` - Para priorizar revisión
- `ix_oi_city` en `(city_id)`

**Estados de parsing (`parse_status`):**

| Valor | Descripción | Acción |
|-------|-------------|--------|
| `pending` | Pendiente de procesar | Parser debe procesar |
| `parsed` | Parseado exitosamente | Listo para crear pedido |
| `needs_review` | Requiere revisión manual | Operador debe verificar |
| `rejected` | Rechazado (spam, inválido) | No procesar |

**Nivel de confianza:**
- `90-100`: Alta confianza, puede crear pedido automáticamente
- `70-89`: Media confianza, mejor revisar
- `< 70`: Baja confianza, requiere revisión manual

---

### `ingest.intent_order_link`

Vincula un order_intent con el pedido creado.

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `order_intent_id` | `uuid` | NO | - | PK y FK a `ingest.order_intent` |
| `order_id` | `uuid` | NO | - | FK a `core.order` |
| `linked_at` | `timestamptz` | NO | `now()` | Fecha de vinculación |
| `linked_by_auth` | `uuid` | SÍ | - | Usuario que aprobó/creó |

**Constraints:**
- `PRIMARY KEY (order_intent_id)`
- `FOREIGN KEY (order_intent_id) REFERENCES ingest.order_intent(id) ON DELETE CASCADE`
- `FOREIGN KEY (order_id) REFERENCES core.order(id) ON DELETE CASCADE`

**Notas:**
- Permite trazabilidad: de qué mensaje vino cada pedido
- Útil para auditoría y resolución de problemas

---

## Vistas

### `ingest.v_inbox`

Bandeja de entrada para revisión de mensajes parseados.

| Columna | Origen | Descripción |
|---------|--------|-------------|
| `order_intent_id` | `order_intent.id` | ID del intent |
| `sent_at` | `message.sent_at` | Fecha del mensaje |
| `from_phone` | `message.from_phone` | Remitente |
| `raw_text` | `message.raw_text` | Texto original |
| `status` | `order_intent.status` | Estado del parsing |
| `confidence` | `order_intent.confidence` | Nivel de confianza |
| `recipient_name` | `order_intent.recipient_name` | Destinatario |
| `recipient_phone` | `order_intent.recipient_phone` | Teléfono destino |
| `address_text` | `order_intent.address_text` | Dirección |
| `amount_gs` | `order_intent.amount_gs` | Monto |
| `delivery_by` | `order_intent.delivery_by` | Fecha límite |
| `city_name` | `city.name` | Ciudad detectada |

**Ordenamiento:**
1. `needs_review` primero
2. Luego `pending`
3. Luego `parsed`
4. Finalmente otros estados
5. Dentro de cada grupo, más recientes primero

**Uso típico:**
```sql
-- Ver mensajes que requieren revisión
SELECT * FROM ingest.v_inbox WHERE status = 'needs_review';

-- Ver últimos mensajes parseados exitosamente
SELECT * FROM ingest.v_inbox WHERE status = 'parsed' LIMIT 10;
```

---

## Flujo de Ingesta

```
┌─────────────────────────────────────────────────────────────────┐
│                     WEBHOOK WHATSAPP                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. RECEPCIÓN                                                    │
│    - Se crea registro en ingest.message                         │
│    - Si hay ubicación, se guarda en message_location            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. PARSING (n8n / función)                                      │
│    - Se analiza raw_text con IA o regex                         │
│    - Se extrae: nombre, teléfono, dirección, productos, monto   │
│    - Se detecta ciudad desde ubicación o texto                  │
│    - Se crea order_intent con status según confianza            │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
               confidence >= 90    confidence < 90
                    │                   │
                    ▼                   ▼
            status = 'parsed'   status = 'needs_review'
                    │                   │
                    │                   ▼
                    │           ┌───────────────────┐
                    │           │ REVISIÓN MANUAL   │
                    │           │ Operador verifica │
                    │           └───────────────────┘
                    │                   │
                    └─────────┬─────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. CREACIÓN DE PEDIDO                                           │
│    - Se crea contact, recipient, address                        │
│    - Se crea core.order                                         │
│    - Se crea billing.order_pricing (trigger calcula tarifa)     │
│    - Se crea intent_order_link                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Ejemplos de Mensajes

### Mensaje estructurado (alta confianza ~95%)

```
1- Nombre de quien recibe: Rosa Mersan
2- Teléfono de contacto: +595981414003
3- Dirección de envío: Victor Boettner 210 esq Sacramento, Asunción
4- Productos: 1 x LINTERNA POTENTE CON ZOOM
5- Total a pagar: 185.000 PYG
6- Ubicación: [coordenadas adjuntas]
```

### Mensaje mínimo (confianza media ~70%)

```
200 mil
Antes de las 12 hs
[Ubicación de WhatsApp]
```

En este caso:
- `amount_gs`: 200.000
- `window_end`: 12:00 del día
- `city_id`: Se determina desde las coordenadas de la ubicación

### Mensaje ambiguo (baja confianza ~50%)

```
Hola, necesito enviar un paquete mañana
```

Esto generaría `status = 'needs_review'` porque falta información crítica.

---

## Notas para Desarrolladores

### Integración con n8n

El flujo típico en n8n sería:

1. **Trigger**: Webhook recibe mensaje de WhatsApp API
2. **Nodo 1**: Insertar en `ingest.message`
3. **Nodo 2**: Si hay ubicación, insertar en `message_location`
4. **Nodo 3**: Llamar a IA/parser para extraer datos
5. **Nodo 4**: Insertar `order_intent` con datos parseados
6. **Nodo 5**: Si `confidence >= 90`, crear pedido automáticamente

### Detección de ciudad desde coordenadas

```sql
-- Usando PostGIS para encontrar la zona que contiene el punto
SELECT z.id, z.name, c.id as city_id, c.name as city_name
FROM ref.zone z
JOIN ref.city c ON c.id = z.city_id
WHERE ST_Contains(z.polygon, ST_SetSRID(ST_MakePoint(-57.6359, -25.2867), 4326));

-- Si no hay zona con polígono, usar distancia a la ciudad más cercana
-- (requiere que las ciudades tengan un punto de referencia)
```

### Alias de ciudades para parsing

Los alias en `ref.city_alias` ayudan al parser:
- "Fdo" → Fernando de la Mora
- "MRA" → Mariano Roque Alonso
- "Asun" → Asunción


# Mejoras App Riders - Análisis Completo

## Contexto

La app de riders es la **pieza operativa clave** del sistema FitoXpress. Los riders actualizan estados durante el día, lo cual alimenta directamente el módulo de rendiciones en el Admin Panel.

### Flujo Operativo Actual

```
Admin (crear pedido) → Asignar rider → App Riders (cambiar estados) → Admin (rendición)
```

La app actual fue desarrollada como MVP y necesita mejoras para:
1. Soportar todos los estados del dominio
2. Registrar correctamente los cobros
3. Facilitar la operativa diaria del rider
4. Mejorar la experiencia de usuario

---

## Problemas Identificados

### 🔴 Críticos (Afectan Rendiciones)

#### 1. Problema de Rendimiento N+1
El provider hace queries individuales en loops:

```dart
// assignments_provider.dart - Línea 68-83
for (final assignment in assignmentsList) {
  final order = await client.from('order').select(...).eq('id', orderId);
  // + query para address
  // + query para city
  // + query para recipient
  // + query para contact
  // + query para order_item
}
```

**Impacto**: Con 20 asignaciones = ~100+ queries a la base de datos.

#### 2. Estados Incompletos

Estados actuales en `assignment_controller.dart`:
| Estado App | Mapea a delivery_status |
|------------|------------------------|
| accepted | recepcionado |
| picked_up | recepcionado |
| en_route | en_transito |
| delivered | entregado |
| failed | rechazado_puerta |

**Estados faltantes del dominio:**
| Estado | Descripción | ¿Cobra tarifa? |
|--------|-------------|----------------|
| `no_atiende` | Cliente no atiende, auto-reagenda al siguiente día | ❌ No |
| `para_devolucion` | Múltiples intentos fallidos, retorno al merchant | ❌ No |
| `reagendado` | Reagendado manualmente a otra fecha | - |
| `cancelado_previo` | Cancelado antes de que el rider salga | ❌ No |
| `extraviado` | Pedido perdido | - |

#### 3. No Registra Cobros

Cuando el rider marca "entregado", debería:
1. ✅ Actualizar `ops.assignment.status` → **Sí lo hace**
2. ✅ Actualizar `core.order.delivery_status` → **Sí lo hace**
3. ❌ Actualizar `core.order.cash_status = 'cobrado'` → **NO lo hace**
4. ❌ Crear registro en `billing.collection` → **NO lo hace**
5. ❌ Registrar timestamp `delivered_at` → **NO lo hace**

**Impacto**: El admin no puede ver correctamente el método de pago ni el monto cobrado en rendiciones.

#### 4. No Registra Timestamps

La tabla `ops.assignment` tiene:
- `accepted_at`
- `picked_up_at`
- `delivered_at`

Pero el controller solo actualiza `status`, ignorando estos campos.

---

### 🟡 Media Prioridad (UX/Funcionalidad)

#### 5. Sin Logout ni Perfil
- No hay forma de cerrar sesión
- No se muestra quién está logueado
- No hay manejo de sesión expirada

#### 6. Información Incompleta en Detalle

Información que **existe en la DB pero no se muestra**:
| Campo | Tabla | Estado |
|-------|-------|--------|
| Nombre del merchant | `core.merchant.name` | ❌ Falta (hardcoded como "Cliente") |
| Notas de referencia | `core.address.reference_notes` | ❌ Falta |
| Número de casa | `core.address.number` | ❌ Falta |
| URL de Google Maps | `core.address.google_maps_url` | ❌ Falta (botón no implementado) |
| Cuenta bancaria | `core.bank_account` | ❌ Falta |
| Fecha programada | `core.order.scheduled_date` | ❌ Falta |
| Notas del pedido | `core.order.notes` | ❌ Falta |

#### 7. Sin Resumen del Día
El rider no puede ver:
- Total de efectivo a cobrar
- Total en transferencias
- Cuántos pedidos completó vs pendientes

#### 8. Sin Lista de Locales (Merchants)
Los riders solicitaron ver:
- Lista de locales donde recoger pedidos
- Dirección de retiro (pickup)
- Teléfono del local
- Ubicación en Maps

---

### 🟢 Baja Prioridad (Nice to Have)

#### 9. Paginación / Lista Infinita
Actualmente la app carga todas las asignaciones de una vez. Con muchos pedidos esto puede:
- Hacer la carga inicial muy lenta
- Consumir mucha memoria
- Afectar el rendimiento del scroll

**Solución**: Implementar paginación con scroll infinito (load more al llegar al final).

#### 10. Funcionalidades de UX
- Pull-to-refresh
- Filtros por estado
- Historial de entregas

#### 11. Notas Personales del Rider
Los riders solicitaron poder anotar ayuda-memoria en cada pedido.

---

## Estructura de Base de Datos Relevante

### Datos ya disponibles para usar

```sql
-- Cuentas bancarias del merchant
core.bank_account
├── bank_name          -- "Banco Itau"
├── holder_name        -- "Juan Pérez"
├── account_number     -- "320305784"
├── alias_type         -- 'correo' | 'celular'
├── alias_value        -- "alias@email.com"
├── is_default         -- true/false
└── is_active          -- true/false

-- Dirección con referencias
core.address
├── street             -- "Av. España"
├── number             -- "1234"
├── neighborhood       -- "Centro"
├── reference_notes    -- "Casa blanca, portón negro"
├── google_maps_url    -- "https://maps.app.goo.gl/..."
└── city_id            -- FK a ref.city

-- Pedido con fecha programada
core.order
├── scheduled_date     -- '2025-01-15'
├── notes              -- "Entregar después de las 14hs"
├── cash_to_collect_gs -- 150000
└── cash_status        -- 'sin_cobro' | 'cobrado'
```

### Tabla nueva requerida: Notas del Rider

```sql
CREATE TABLE ops.rider_note (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES ops.assignment(id) ON DELETE CASCADE,
    courier_id UUID NOT NULL REFERENCES ops.courier(id),
    note TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_rider_note_assignment ON ops.rider_note(assignment_id);

ALTER TABLE ops.rider_note ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Riders can manage their own notes"
ON ops.rider_note FOR ALL
USING (courier_id IN (
    SELECT id FROM ops.courier WHERE auth_user_id = auth.uid()
));
```

---

## Arquitectura Propuesta

### Estructura de Pantallas

```
📱 App Riders
│
├── 🏠 Home (AssignmentsScreen)
│   ├── [Header con perfil del rider]
│   │   └── Nombre + botón logout
│   │
│   ├── [Resumen del día]  ← NUEVO
│   │   ├── 📦 Total pedidos: 12
│   │   ├── 💵 Efectivo: Gs. 450.000
│   │   ├── 📲 Transferencias: Gs. 200.000
│   │   └── ✅ Entregados: 5/12
│   │
│   └── [Lista de asignaciones]
│       └── AssignmentCard (mejorada)
│           ├── Indicador efectivo/transferencia
│           └── Merchant name
│
├── 📦 Detalle Pedido (AssignmentDetailScreen)
│   ├── [Estado actual con colores]
│   │
│   ├── [Destinatario]
│   │   ├── Nombre
│   │   ├── Teléfono + [Llamar ☎️]
│   │
│   ├── [Ubicación de Entrega]
│   │   ├── Ciudad
│   │   ├── Dirección + Número
│   │   ├── Referencias (reference_notes)
│   │   └── [Ver en Maps 🗺️]
│   │
│   ├── [Detalle del Pedido]
│   │   ├── Merchant (nombre del local)
│   │   ├── Artículos
│   │   ├── Monto a cobrar
│   │   ├── Tipo: Efectivo / Transferencia
│   │   └── Fecha programada (si aplica)
│   │
│   ├── [Cuenta Bancaria]  ← NUEVO (solo si es transferencia)
│   │   ├── Banco
│   │   ├── Titular
│   │   ├── Cuenta o Alias
│   │   └── [Copiar 📋]
│   │
│   ├── [Mis Notas]  ← NUEVO
│   │   └── Campo de texto editable
│   │
│   └── [Acciones]
│       └── Cambiar estado (todos los estados)
│
├── 🏪 Locales (MerchantsScreen)  ← NUEVA PANTALLA
│   └── Lista de merchants con pedidos asignados
│       ├── Nombre del local
│       ├── Dirección de retiro
│       ├── [Ver en Maps 🗺️]
│       └── [Llamar ☎️]
│
└── 👤 Perfil (ProfileScreen)  ← NUEVA PANTALLA
    ├── Foto/Avatar
    ├── Nombre del rider
    ├── Teléfono
    ├── Vehículo
    └── [Cerrar sesión]
```

### Entidad Assignment Mejorada

```dart
class Assignment {
  final String id;
  final String orderId;
  final String assignmentStatus;      // Estado de la asignación
  final String deliveryStatus;        // Estado del pedido

  // Merchant
  final String merchantId;
  final String merchantName;

  // Destinatario
  final String recipientName;
  final String recipientPhone;

  // Ubicación
  final String city;
  final String street;
  final String? number;
  final String? neighborhood;
  final String? referenceNotes;
  final String? googleMapsUrl;

  // Monto y pago
  final int cashToCollect;
  final String? paymentMethod;        // 'cash' | 'transfer'
  final bool isPaid;

  // Producto
  final String productDescription;

  // Información adicional
  final String? scheduledDate;
  final String? orderNotes;
  final String? riderNote;            // Nota personal del rider

  // Cuenta bancaria (para transferencias)
  final BankAccount? bankAccount;

  // Pickup (local de retiro)
  final PickupLocation? pickupLocation;

  // Timestamps
  final DateTime assignedAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
}

class BankAccount {
  final String? bankName;
  final String? holderName;
  final String? accountNumber;
  final String? aliasType;
  final String? aliasValue;
}

class PickupLocation {
  final String merchantName;
  final String street;
  final String? number;
  final String city;
  final String? phone;
  final String? googleMapsUrl;
}
```

---

## Plan de Implementación

### Fase 1: Core (Crítico para Rendiciones)
**Tiempo estimado: 10-12 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 1.1 | Optimizar queries (eliminar N+1) | 🔴 |
| 1.2 | Implementar paginación / lista infinita | 🔴 |
| 1.3 | Agregar todos los estados faltantes | 🔴 |
| 1.4 | Registrar `cash_status` al entregar | 🔴 |
| 1.5 | Crear registro en `billing.collection` | 🔴 |
| 1.6 | Registrar timestamps (delivered_at, etc.) | 🔴 |
| 1.7 | Preguntar método de pago al marcar entregado | 🔴 |

### Fase 2: Sesión y Navegación
**Tiempo estimado: 3-4 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 2.1 | Agregar logout | 🔴 |
| 2.2 | Crear pantalla de perfil | 🟡 |
| 2.3 | Mostrar nombre del rider en header | 🟡 |
| 2.4 | Manejo de sesión expirada | 🟡 |
| 2.5 | Verificar rol 'rider' al login | 🟡 |

### Fase 3: Información Completa
**Tiempo estimado: 4-5 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 3.1 | Mostrar cuenta bancaria del merchant | 🟡 |
| 3.2 | Mostrar referencias y número de casa | 🟡 |
| 3.3 | Implementar botón de Google Maps | 🟡 |
| 3.4 | Implementar botón de llamada | 🟡 |
| 3.5 | Mostrar nombre del merchant | 🟡 |
| 3.6 | Mostrar fecha programada y notas | 🟡 |

### Fase 4: Resumen y Locales
**Tiempo estimado: 4-5 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 4.1 | Widget de resumen del día (efectivo/transfer) | 🟡 |
| 4.2 | Pantalla de locales (merchants) | 🟡 |
| 4.3 | Pull-to-refresh | 🟡 |

### Fase 5: Notas del Rider
**Tiempo estimado: 3-4 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 5.1 | Crear migración tabla `ops.rider_note` | 🟢 |
| 5.2 | Implementar UI de notas personales | 🟢 |
| 5.3 | CRUD de notas | 🟢 |

### Fase 6: Mejoras de UX
**Tiempo estimado: 2-3 horas**

| # | Tarea | Prioridad |
|---|-------|-----------|
| 6.1 | Filtros por estado | 🟢 |
| 6.2 | Historial de entregas | 🟢 |
| 6.3 | Mejoras visuales/animaciones | 🟢 |

---

## Tiempo Total Estimado

| Fase | Tiempo |
|------|--------|
| Fase 1: Core + Paginación | 10-12 horas |
| Fase 2: Sesión | 3-4 horas |
| Fase 3: Info Completa | 4-5 horas |
| Fase 4: Resumen/Locales | 4-5 horas |
| Fase 5: Notas | 3-4 horas |
| Fase 6: UX | 2-3 horas |
| **Total** | **26-33 horas** |

---

## Dependencias Técnicas

### Packages Flutter Sugeridos

```yaml
# pubspec.yaml
dependencies:
  url_launcher: ^6.2.0      # Abrir Maps y llamadas
  intl: ^0.19.0             # Formateo de fechas y monedas
  flutter_riverpod: ^2.5.0  # Ya instalado
  go_router: ^13.0.0        # Ya instalado
  supabase_flutter: ^2.0.0  # Ya instalado
```

### Implementación de Paginación

#### Query con Paginación en Supabase

```dart
// Parámetros de paginación
const int pageSize = 20;

Future<List<Assignment>> fetchAssignments({int page = 0}) async {
  final from = page * pageSize;
  final to = from + pageSize - 1;

  final response = await supabase
      .schema('ops')
      .from('assignment')
      .select('...')
      .eq('courier_id', courierId)
      .eq('settled_with_rider', false)  // Solo pendientes
      .order('assigned_at', ascending: false)
      .range(from, to);  // Paginación

  return response.map((e) => Assignment.fromJson(e)).toList();
}
```

#### Estado con Riverpod para Lista Infinita

```dart
class AssignmentsState {
  final List<Assignment> assignments;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  // Constructor y copyWith...
}

class AssignmentsNotifier extends StateNotifier<AssignmentsState> {
  AssignmentsNotifier() : super(AssignmentsState.initial());

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    final newItems = await _fetchAssignments(page: state.currentPage);

    state = state.copyWith(
      assignments: [...state.assignments, ...newItems],
      currentPage: state.currentPage + 1,
      hasMore: newItems.length == pageSize,
      isLoading: false,
    );
  }

  Future<void> refresh() async {
    state = AssignmentsState.initial().copyWith(isLoading: true);
    await loadMore();
  }
}
```

#### Widget con Scroll Infinito

```dart
ListView.builder(
  controller: _scrollController,  // Detectar fin del scroll
  itemCount: assignments.length + (hasMore ? 1 : 0),
  itemBuilder: (context, index) {
    if (index == assignments.length) {
      // Loader al final
      return const Center(child: CircularProgressIndicator());
    }
    return AssignmentCard(assignment: assignments[index]);
  },
)
```

### Cambios en Admin Panel

Para sincronía completa, el Admin Panel debería:
1. Poder ver las notas personales del rider (solo lectura)
2. El campo de método de pago debería pre-popularse con lo que registró el rider

---

## Notas Adicionales

### Offline Support (Futuro)
Considerar para una versión futura:
- Cache local de asignaciones
- Cola de actualizaciones offline
- Sincronización al recuperar conexión

### Notificaciones Push (Futuro)
- Nueva asignación
- Cambios en pedidos
- Alertas de rendición pendiente

---

## Checklist de Validación

Antes de dar por completada cada fase:

- [ ] Probar en Android
- [ ] Probar en iOS (si aplica)
- [ ] Verificar que las rendiciones en Admin muestran datos correctos
- [ ] Verificar RLS en tablas nuevas
- [ ] Revisar manejo de errores
- [ ] Verificar que no hay linter errors


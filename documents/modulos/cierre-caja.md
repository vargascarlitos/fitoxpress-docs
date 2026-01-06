# Módulo de Cierre de Caja

Este módulo gestiona el cierre financiero diario, calculando las ganancias y gastos por tipo de rider.

---

## Conceptos Clave

### Tipos de Rider

| Tipo | Descripción | Cálculo de Ganancia |
|------|-------------|---------------------|
| **Fijo** (`fixed`) | Sueldo mensual fijo | Ingresos - Salario diario - Plus - Gastos |
| **Comisionista** (`commission`) | Cobra % por entrega | Ingresos × (1 - commission_rate) |

### Estados que Generan Ingreso

Solo estos estados entran en el cierre de caja (rider llegó físicamente):

| Estado | Descripción | ¿Cobra tarifa? |
|--------|-------------|----------------|
| `entregado` | Entrega completada | ✅ Sí |
| `rechazado_puerta` | Cliente rechazó (rider llegó) | ✅ Sí |

### Fecha para Contabilidad

El campo `fecha_para_contabilidad` en `core.order` determina en qué día se contabiliza el ingreso:

- Se llena **automáticamente** mediante trigger cuando el pedido pasa a `entregado` o `rechazado_puerta`
- Representa el día **real** en que el rider completó la visita
- Es la fuente de verdad para el cierre de caja

---

## Estructura de Datos

### Tablas Principales

| Esquema | Tabla | Propósito |
|---------|-------|-----------|
| `ref` | `holiday` | Feriados de Paraguay |
| `billing` | `bonus_rule` | Escala de plus por entregas |
| `ops` | `courier_expense` | Gastos por rider fijo |
| `ops` | `salary_advance` | Adelantos de salario |
| `billing` | `general_expense` | Gastos generales empresa |
| `billing` | `daily_cash_closing` | Registro de cierres |

### Campos Financieros en Courier

```sql
-- En ops.courier
rider_type         -- 'fixed' o 'commission'
monthly_salary_gs  -- Salario mensual (solo fijos)
commission_rate    -- Tasa de comisión (solo comisionistas)
```

---

## Cálculos Financieros

### Riders Fijos

```
Salario Diario = monthly_salary_gs / días_laborables_del_mes

Plus = MAX(amount_gs) FROM bonus_rule WHERE min_orders <= entregas_del_día

Ganancia Neta = Ingresos - Salario Diario - Plus - Gastos Operativos
```

### Riders Comisionistas

```
Comisión Rider = Ingresos × commission_rate  (ej: 70%)

Ganancia Empresa = Ingresos × (1 - commission_rate)  (ej: 30%)
```

### Días Laborables

```sql
-- Función: billing.get_working_days_count(year, month)
días_laborables = días_del_mes - domingos - feriados_no_domingo
```

---

## Flujo de Cierre Diario

```
1. Operador marca pedido como ENTREGADO o RECHAZADO_PUERTA
        ↓
2. Trigger automático llena fecha_para_contabilidad = HOY
        ↓
3. Admin consulta el reporte del día
        ↓
4. Sistema calcula:
   • Ingresos por rider (tarifas cobradas)
   • Costos fijos (salarios, plus, gastos)
   • Comisiones (% para comisionistas)
   • Gastos generales
        ↓
5. Ganancia Neta = Ingresos - Todos los Costos
```

---

## API (Funciones RPC)

### `get_daily_profit_report(p_report_date)`

Genera el reporte financiero completo para una fecha.

**Llamada desde el cliente:**

```typescript
const { data, error } = await supabase
  .rpc('get_daily_profit_report', { p_report_date: '2026-01-05' });
```

**Respuesta:**

```json
{
  "report_date": "2026-01-05",
  "working_days_in_month": 26,
  "fixed_riders": [...],
  "commission_riders": [...],
  "expenses": {
    "fixed_riders_expenses": 0,
    "general_expenses": 0
  },
  "summary": {
    "total_income": 285000,
    "fixed_costs": {
      "daily_salaries": 446152,
      "bonuses": 0,
      "expenses": 0,
      "total": 446152
    },
    "commission_costs": {
      "commission_paid": 70000
    },
    "general_expenses": 0,
    "net_profit": -231152
  }
}
```

### `get_working_days_count(p_year, p_month)`

Calcula días laborables de un mes.

```typescript
const { data } = await supabase
  .rpc('get_working_days_count', { p_year: 2026, p_month: 1 });
// data = 26
```

---

## Escala de Plus (Bonificaciones)

La tabla `billing.bonus_rule` define los niveles de plus diario:

| Entregas | Plus |
|----------|------|
| 12+ | 50.000 Gs |
| 15+ | 75.000 Gs |
| 18+ | 100.000 Gs |
| 21+ | 125.000 Gs |
| 24+ | 150.000 Gs |

**Lógica:** Se toma el MAX del plus aplicable según entregas del día.

---

## Restricciones de Seguridad (RLS)

Solo usuarios con rol `admin` pueden:
- Ver datos de `billing.bonus_rule`
- Ver/crear datos de `ops.courier_expense`
- Ver/crear datos de `ops.salary_advance`
- Ver/crear datos de `billing.general_expense`
- Ver/crear datos de `billing.daily_cash_closing`

---

## Triggers Automáticos

### `trg_set_fecha_contabilidad`

**Tabla:** `core.order`
**Evento:** `BEFORE UPDATE`

Automáticamente llena `fecha_para_contabilidad = CURRENT_DATE` cuando:
- `delivery_status` cambia a `entregado`
- `delivery_status` cambia a `rechazado_puerta`

### `trg_expense_only_fixed`

**Tabla:** `ops.courier_expense`
**Evento:** `BEFORE INSERT`

Valida que el courier sea de tipo `fixed` antes de registrar gastos.

### `trg_advance_only_fixed`

**Tabla:** `ops.salary_advance`
**Evento:** `BEFORE INSERT`

Valida que el courier sea de tipo `fixed` antes de registrar adelantos.

---

## Ejemplo de Cierre

### Datos del Día

| Rider | Tipo | Entregas | Tarifas |
|-------|------|----------|---------|
| Hugo | fixed | 5 | 125.000 Gs |
| Marcio | fixed | 3 | 75.000 Gs |
| Santi | commission | 4 | 100.000 Gs |

### Configuración

- Salario mensual fijos: 2.900.000 Gs
- Días laborables enero: 26
- Comisión: 70%

### Cálculo

**Riders Fijos:**
```
Salario diario = 2.900.000 / 26 = 111.538 Gs (por rider)

Hugo: 125.000 - 111.538 = +13.462 Gs
Marcio: 75.000 - 111.538 = -36.538 Gs

Total Fijos: -23.076 Gs
```

**Riders Comisionistas:**
```
Santi: 100.000 × 0.30 = 30.000 Gs (empresa)
       100.000 × 0.70 = 70.000 Gs (rider)
```

**Ganancia Total:**
```
Ingresos: 125.000 + 75.000 + 100.000 = 300.000 Gs
Egresos: 111.538 + 111.538 + 70.000 = 293.076 Gs
Ganancia: 300.000 - 293.076 = 6.924 Gs
```

---

## Notas para Desarrolladores

### Frontend (Angular)

El componente `FinanceDashboardComponent` consume el RPC y muestra:
- Selector de fecha
- Tarjetas de resumen por tipo de rider
- Detalle por rider individual
- Totales de ingresos/egresos/ganancia

### Interfaces TypeScript

```typescript
interface FixedRiderDetail {
  courier_id: string;
  courier_name: string;
  deliveries: number;
  fees_gs: number;
  daily_salary_gs: number;
  bonus_gs: number;
}

interface CommissionRiderDetail {
  courier_id: string;
  courier_name: string;
  commission_rate: number;
  deliveries: number;
  fees_gs: number;
  rider_earnings_gs: number;
  company_profit_gs: number;
}
```

### Consideraciones

1. **Ganancia puede ser negativa** - Si los costos fijos superan los ingresos
2. **Plus se calcula por día** - No acumulativo
3. **Gastos de riders** - Solo aplican a fijos
4. **Comisión** - El rider se queda con el % definido (ej: 70%)


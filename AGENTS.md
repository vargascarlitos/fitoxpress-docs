# FitoXpress - Global Agent Rules

> This document provides the business context, domain language, and shared rules that any agent (or developer) must understand when working on the FitoXpress ecosystem.

---

## 1. What is FitoXpress?

FitoXpress is a Paraguayan logistics and delivery platform for **non-gastronomic businesses**. It centralizes daily operations including:

- **Order reception** via WhatsApp (manual today, automated tomorrow).
- **Rider assignment** by city and zone.
- **Mixed payment management**:
  - Cash collected by riders.
  - Bank transfers that go directly to the merchant.
- **Daily reconciliation**:
  - With riders (cash on hand).
  - With merchants (net settlement after deducting delivery fees).

**The business focus is NOT food delivery**, but shipments for stores, entrepreneurs, and retail businesses that sell through social media.

### One-liner description

> FitoXpress is an internal logistics system that allows businesses to sell via WhatsApp while the company controls orders, riders, and money without depending on Excel.

---

## 2. The Problem It Solves

Before FitoXpress, the business operated with:
- WhatsApp as the main channel.
- Excel as the operating system (order entry, daily closings, cash reconciliation).
- Heavy reliance on human memory (Who collected cash? Which order was a transfer? How much does each rider owe?).

This caused:
- Reconciliation errors.
- Difficulty scaling.
- Lack of traceability and audit trails.
- Dependency on key people.

FitoXpress organizes this operation without changing the merchant's sales channel.

---

## 3. Operational Model

### Real Order Flow

```
1. Merchant receives order via WhatsApp
        ↓
2. Merchant sends data to FitoXpress
        ↓
3. FitoXpress:
   • Registers the order
   • Auto-calculates delivery fee (city/zone/merchant)
   • Assigns an eligible rider for that zone
        ↓
4. Rider delivers the order
        ↓
5. Customer pays:
   • Cash to rider, OR
   • Bank transfer directly to merchant
        ↓
6. End of day:
   • Rider renders cash on hand
   • FitoXpress deducts delivery fee
   • Daily closing generated per merchant
```

### Critical Business Point

The most sensitive point is: **Cash reconciliation collected by riders**.

Because:
- Cash passes physically through the rider.
- Transfers do not.
- On the same day there are: cash orders, transfer orders, different riders, different merchants.

**The platform exists primarily to solve this problem reliably.**

---

## 4. Domain Language (Terminology)

| Term | Definition |
|------|------------|
| **Merchant** | Store or business that originates the order. |
| **Rider / Courier** | Delivery person responsible for the shipment. |
| **Recipient** | End customer who receives the order. |
| **Order** | Central entity representing a delivery. |
| **Order Item** | Products contained in an order. |
| **Assignment** | The link between an order and a specific rider. |
| **Rendition** | Cash accountability process (Rider → Admin, or settlement → Merchant). |
| **Settlement** | Financial closing with a merchant for a period. |
| **Payout** | Payment to a rider for completed deliveries. |

---

## 5. User Roles (`app_role`)

| Role | Description | Platform Access |
|------|-------------|-----------------|
| `admin` | Full system control. Tariffs, closings, audit. | Admin Panel |
| `operator` | Loads orders, assigns riders, registers collections. | Admin Panel |
| `merchant` | Views their orders and settlements. | (Future: Merchant Portal) |
| `rider` | Views assigned orders, delivery history, earnings. | Riders App (Flutter) |

---

## 6. Critical States

### Delivery Status (`delivery_status`)

| Status | Description | Enters Daily Closing? |
|--------|-------------|----------------------|
| `recepcionado` | Order received, pending assignment | No |
| `en_transito` | Rider on the way | No |
| `entregado` | Successfully delivered | **Yes** |
| `rechazado_puerta` | Customer rejected at door (fee charged to merchant) | **Yes** |
| `cancelado_previo` | Cancelled before rider departure (no fee) | No |
| `reagendado` | Rescheduled for another date | No |
| `extraviado` | Order lost | No |

**Key distinction:**
- `rechazado_puerta`: Rider **arrived physically** → Fee IS charged.
- `cancelado_previo`: Rider contacted before leaving → Fee NOT charged.

### Cash Status (`cash_status`)

| Status | Description |
|--------|-------------|
| `sin_cobro` | No collection applicable or already paid online |
| `cobrado` | Cash collected by rider |

---

## 7. Database Structure (Supabase)

### MCP Access (Development)
A Supabase MCP server is available for querying the development database directly. Use it to:
- Verify current table structures
- Check data before/after operations
- Validate migrations
- Explore relationships

**Available MCP tools:**
- `list_tables` - List tables by schema
- `execute_sql` - Run SELECT queries
- `apply_migration` - Apply DDL changes
- `list_migrations` - View migration history
- `get_logs` - Debug with service logs
- `search_docs` - Search Supabase documentation

⚠️ **Always verify documentation against the live database** - the MCP is the source of truth.

### Schema Organization
Data is organized in logical schemas. **DO NOT create tables in `public` without authorization.**

| Schema | Purpose | Key Tables |
|--------|---------|------------|
| `core` | Main entities | `order`, `merchant`, `recipient`, `user_profile`, `bank_account`, `rendition_note` |
| `ops` | Logistics operations | `courier`, `assignment`, `rider_payout`, `courier_city` |
| `billing` | Billing and tariffs | `order_pricing`, `settlement`, `collection`, `merchant_city_rate` |
| `ref` | Master data | `city`, `zone`, `city_rate`, `zone_rate` |
| `ingest` | WhatsApp message processing | `message`, `order_intent`, `channel` |
| `audit` | Audit logs | `event` |

### Active Extensions
- **uuid-ossp**: UUID generation
- **pgcrypto**: Cryptographic functions
- **postgis**: Geospatial data (GPS coordinates)

---

## 8. Platform Philosophy

### 1. Separate Operation from Money
- Order ≠ Collection ≠ Settlement
- Every money movement is: recorded, auditable, reconcilable.

### 2. Automate Manual Tasks
- Delivery fee calculation
- Daily closings
- Totals and subtotals
- Validations (rider eligible for zone, order not settled twice, etc.)

### 3. Ready to Grow, Not Required Today
- Today: manually loaded orders
- Tomorrow: WhatsApp bot, rider app ✓, merchant portal
- The model is already designed for this.

---

## 9. What FitoXpress is NOT

- ❌ NOT a consumer app like PedidosYa / Uber Eats.
- ❌ Does NOT manage product catalogs or online payments.
- ❌ Does NOT replace the merchant's WhatsApp.
- ❌ Does NOT process bank transfers (only records them).

**It IS an operational and financial control system for urban logistics.**

---

## 10. Code Standards (ALL Projects)

### Language
- **Code**: English (variables, functions, classes, comments).
- **UI/Messages**: Spanish (user-facing text).
- **Currency**: Guaraníes (Gs).

### Comments
- Minimal comments. Code should be self-documenting.
- Only comment complex business logic or non-obvious decisions.
- NO commented-out code in commits.

### Testing
- Not a priority for MVP phase.
- Focus on working features first.

### Naming Conventions
- Use descriptive names that explain intent.
- Avoid abbreviations unless universally understood.
- Follow each project's specific conventions (see project-level agents.md).

### Database First
- Complex data logic should reside in the database (RLS, Triggers, Functions) or backend services.
- Keep clients "dumb" when possible.
- Always use UUIDs for primary identifiers.

---

## 11. Current System Components

| Component | Technology | Status |
|-----------|------------|--------|
| Admin Panel | Angular 20+ | ✅ Active |
| Riders App | Flutter + Riverpod | ✅ Active |
| Database | Supabase (PostgreSQL) | ✅ Active |
| WhatsApp Bot | (Planned) | 🔜 Future |
| Merchant Portal | (Planned) | 🔜 Future |

---

## 12. Related Documentation

- [Database Schemas](documents/README.md)
- [Core Schema](documents/schemas/core.md)
- [Ops Schema](documents/schemas/ops.md)
- [Billing Schema](documents/schemas/billing.md)
- [Orders Module](documents/modulos/pedidos.md)

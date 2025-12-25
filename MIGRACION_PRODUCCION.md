# 🚀 Guía de Migración a Producción - FitoXpress

## Estado Actual

| Ambiente | Proyecto | Estado |
|----------|----------|--------|
| **Development/Staging** | `fitoxpress` (crvqpztzddxktyjukeph) | ✅ Activo |
| **Local** | Docker | ✅ Configurado |
| **Production** | `fitoxpress-prod` | ⏳ Por crear |

---

## 📋 Paso a Paso: Crear Ambiente de Producción

### Paso 1: Crear el proyecto de producción en Supabase

1. Ve a [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click en **"New Project"**
3. Selecciona la organización **fitoXpress**
4. Configura:
   - **Name**: `fitoxpress-prod`
   - **Database Password**: Genera una contraseña segura y **guárdala en un lugar seguro** (ej: 1Password, Bitwarden)
   - **Region**: `us-east-1` (igual que desarrollo)
5. Click en **"Create new project"**
6. Espera ~2 minutos a que el proyecto esté listo
7. Copia el **Project ID** de la URL: `https://supabase.com/dashboard/project/<PROJECT_ID>`

---

### Paso 2: Habilitar extensiones necesarias en producción

En el Dashboard de producción, ve a **SQL Editor** y ejecuta:

```sql
-- Habilitar PostGIS (requerido para geometrías)
CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "public";

-- Habilitar UUID (por si no está)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
```

---

### Paso 3: Vincular y aplicar migraciones

Desde tu terminal:

```bash
cd /Users/carlosvargas/dev/fitoxpress

# Desvincular del proyecto de desarrollo (si está vinculado)
supabase unlink

# Vincular al proyecto de PRODUCCIÓN
supabase link --project-ref <PROJECT_ID_PRODUCCION>

# Te pedirá la contraseña de la base de datos (la que creaste en el paso 1)

# Aplicar las migraciones
supabase db push
```

---

### Paso 4: Verificar la migración

```bash
# Listar las migraciones aplicadas
supabase migration list
```

Deberías ver:
```
LOCAL      │ REMOTE     │ NAME
───────────┼────────────┼─────────────────────────────────
20240101.. │ 20240101.. │ initial_schema
```

---

### Paso 5: Configurar Auth en Producción

En el Dashboard de producción:

1. **Authentication → URL Configuration**
   - Site URL: `https://tu-dominio-produccion.com`
   - Redirect URLs: Agregar URLs de tu app

2. **Authentication → Email Templates** (si tienes personalizados)
   - Copiar de desarrollo si es necesario

3. **Authentication → Providers** (si usas OAuth)
   - Configurar los mismos proveedores

---

### Paso 6: Crear Storage Buckets (si aplica)

Si usas Storage, crear los mismos buckets en producción:

```sql
-- En SQL Editor de producción
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('pod-images', 'pod-images', false),
  -- Agregar otros buckets que uses
;
```

---

### Paso 7: Obtener credenciales de producción

En Dashboard → **Settings → API**, copia:

- **Project URL**: `https://<PROJECT_ID>.supabase.co`
- **Anon Key**: `eyJ...` (clave pública)
- **Service Role Key**: `eyJ...` (solo para backend, NUNCA en frontend)

---

### Paso 8: Configurar las apps para producción

#### Flutter (fitoxpress-app-riders)

Crear archivo `api-keys.prod.json`:

```json
{
    "SUPABASE_URL": "https://<PROJECT_ID_PROD>.supabase.co",
    "SUPABASE_ANON_KEY": "<ANON_KEY_PRODUCCION>"
}
```

Compilar para producción:
```bash
flutter build apk --dart-define-from-file=api-keys.prod.json
# o para iOS
flutter build ios --dart-define-from-file=api-keys.prod.json
```

#### Angular (fitoxpress-admin)

Actualizar `src/environments/environment.ts`:

```typescript
export const environment = {
  production: true,
  supabaseUrl: 'https://<PROJECT_ID_PROD>.supabase.co',
  supabaseAnonKey: '<ANON_KEY_PRODUCCION>'
};
```

Compilar para producción:
```bash
ng build --configuration=production
```

---

### Paso 9: (Opcional) Migrar datos iniciales

Si tienes datos de catálogo que deben existir en producción:

```bash
# Exportar datos de desarrollo (solo datos, no schema)
supabase db dump --data-only -f data_backup.sql --linked

# Cambiar al proyecto de producción
supabase unlink
supabase link --project-ref <PROJECT_ID_PRODUCCION>

# Importar datos (con cuidado, revisar el archivo primero)
psql <DATABASE_URL_PRODUCCION> -f data_backup.sql
```

---

## 🔄 Flujo de Desarrollo Futuro

```
Local (Docker)  →  Staging (fitoxpress)  →  Production (fitoxpress-prod)
     ↓                    ↓                         ↓
supabase start     supabase db push         supabase db push
     ↓                    ↓                         ↓
Desarrollo         git push develop          git push main
```

### Crear nueva migración

```bash
# 1. Hacer cambios localmente (en Studio local: http://localhost:54323)

# 2. Generar migración
supabase db diff -f nombre_descriptivo

# 3. Probar localmente
supabase db reset

# 4. Commit y push
git add supabase/migrations/
git commit -m "feat: agregar tabla X"
git push

# 5. Desplegar a staging
supabase link --project-ref crvqpztzddxktyjukeph
supabase db push

# 6. Cuando esté listo, desplegar a producción
supabase link --project-ref <PROJECT_ID_PRODUCCION>
supabase db push
```

---

## 📌 URLs de Referencia

| Recurso | Desarrollo | Producción |
|---------|------------|------------|
| Dashboard | [Dashboard Dev](https://supabase.com/dashboard/project/crvqpztzddxktyjukeph) | Dashboard Prod (crear) |
| API URL | `https://crvqpztzddxktyjukeph.supabase.co` | `https://<PROD_ID>.supabase.co` |
| Local Studio | http://localhost:54323 | N/A |

---

## ⚠️ Checklist Pre-Producción

- [ ] Proyecto de producción creado
- [ ] Extensión PostGIS habilitada
- [ ] Migraciones aplicadas
- [ ] RLS (Row Level Security) verificado
- [ ] Auth URLs configuradas
- [ ] Storage buckets creados
- [ ] Variables de entorno en apps actualizadas
- [ ] Dominio/SSL configurado (si aplica)
- [ ] Backups automáticos verificados
- [ ] Monitoring configurado

---

## 🆘 Troubleshooting

### Error: "type geometry does not exist"
```sql
CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "public";
```

### Error: "permission denied"
Verificar que el usuario tenga permisos:
```sql
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres;
```

### Error: "migration already applied"
```bash
supabase migration repair --status reverted <VERSION>
```


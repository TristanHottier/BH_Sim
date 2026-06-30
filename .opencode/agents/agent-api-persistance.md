# Agent — Architecture API & Persistance (Config Presets)

## Rôle
Expert en conception d'API et de schémas de base de données pour persister et partager les configurations de simulation BH_Sim. Tu interviens sur tout ce qui concerne la couche données : schéma Prisma, routes Next.js API, validation Zod, et gestion des presets utilisateur.

---

## Contexte BH_Sim

La simulation expose ces paramètres WebGL uniform :
- `uCamPos` : position caméra (θ, φ, dist)
- `uDiskPsi` : inclinaison du disque (radians)
- `uRealistic` : mode Kepler (bool)
- `uShowShadow` : bordure ombre (bool)
- `uTime` : temps de simulation
- Constants dans shader : `ALPHA`, `M`, `DISK_IN`, `DISK_OUT`, `DISK_SIGMA`, `GM`

---

## Schéma Prisma — modèles principaux

```prisma
model BlackHoleConfig {
  id          String   @id @default(cuid())
  name        String
  slug        String   @unique

  // Paramètres physiques (shader constants)
  alpha       Float    @default(8.0)
  mass        Float    @default(0.5)
  diskInner   Float    @default(1.125)
  diskOuter   Float    @default(25.0)
  diskSigma   Float    @default(0.10)

  // Camera
  camTheta    Float    @default(100.0)
  camPhi      Float    @default(80.0)
  camDist     Float    @default(45.0)

  // Disque
  diskPsi     Float    @default(0.0)
  realistic   Boolean  @default(false)

  // Rendu
  showShadow  Boolean  @default(false)

  // Métadonnées
  isPublic    Boolean  @default(false)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  userId      String?
  user        User?    @relation(fields: [userId], references: [id])
}

model User {
  id        String              @id @default(cuid())
  email     String              @unique
  configs   BlackHoleConfig[]
  createdAt DateTime            @default(now())
}
```

## Validation Zod

```typescript
export const blackHoleConfigSchema = z.object({
  name: z.string().min(1).max(100),
  alpha: z.number().min(1).max(20),
  mass: z.number().min(0.1).max(5),
  diskInner: z.number().min(0.5).max(10),
  diskOuter: z.number().min(5).max(100),
  diskSigma: z.number().min(0.01).max(0.5),
  camTheta: z.number().min(0).max(360),
  camPhi: z.number().min(1).max(179),
  camDist: z.number().min(35).max(100),
  diskPsi: z.number().min(-180).max(180),
  realistic: z.boolean(),
  showShadow: z.boolean(),
  isPublic: z.boolean().default(false),
})
```

## Routes API Next.js (App Router)

```
POST   /api/configs          → créer une configuration
GET    /api/configs          → lister ses configurations
GET    /api/configs/[id]     → récupérer une config
PUT    /api/configs/[id]     → mettre à jour
DELETE /api/configs/[id]     → supprimer
GET    /api/configs/public   → configs publiques (galerie)
POST   /api/configs/[id]/fork → dupliquer une config publique
```

## Partage de configurations (deep link)

```typescript
// URL partageable : /sim/[slug] ou /sim/[id]
// Au chargement, fetch la config et initialiser les uniforms WebGL
const config = await fetch(`/api/configs/${slug}`).then(r => r.json())
// → passer config comme props au composant WebGL canvas
```

## Migrations Prisma

```bash
npx prisma migrate dev --name add_black_hole_config
npx prisma generate
# En production
npx prisma migrate deploy
```

## Variables d'environnement

```env
DATABASE_URL="postgresql://user:password@localhost:5432/bh_sim_db"
NEXTAUTH_SECRET="..."
NEXTAUTH_URL="http://localhost:3000"
```

---

## Checklist avant chaque route API
- [ ] Auth vérifiée (session NextAuth ou route publique explicite)
- [ ] Input validé avec Zod
- [ ] Ownership vérifié (l'user modifie bien SA config)
- [ ] Erreurs Prisma catchées (`PrismaClientKnownRequestError`)
- [ ] Response typée (`NextResponse.json<T>`)

---

## Références
- Prisma Docs — relations, middleware, soft-delete patterns
- Zod + tRPC integration guide
- Next.js App Router — Route Handlers best practices

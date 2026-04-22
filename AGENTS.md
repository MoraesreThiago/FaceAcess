# AGENTS.md — Protocolo para IAs trabalhando neste repositório

> **Leia este arquivo inteiro antes de executar qualquer ação no projeto.**
> Vale para Claude Code, Codex, Copilot Chat, Cursor, e qualquer outro agente que abra este repo.
> Se você for um humano revisando: este arquivo é o contrato entre agentes.

---

## 0. Identidade do projeto em 30 segundos

- **App:** FaceAccess (marca comercial "BemBrasil") — controle de acesso por reconhecimento facial em tablets Android.
- **Dois flavors de APK, mesma base de código:** `admin` (gestão) e `porta` (reconhecimento na parede).
- **Duas unidades:** Araxá (~300 pessoas) e Perdizes (~1000).
- **Stack:** Flutter/Dart 3.3+, Riverpod, Hive (local), Firestore (sync remoto), MQTT (relé ESP32), ML Kit + TFLite FaceNet 512-d.
- **Arquitetura:** Clean architecture frouxa (`domain/` / `application/` / `infrastructure/` / `presentation/`), composition root em `lib/app/providers/`.
- **Estado atual:** em refatoração disciplinada por PRs sequenciais. PR #1 a **PR #7 já em `main`**. Próximo: **PR #8**.

Para o contexto completo, leia `docs/HANDOFF.md` se existir; caso contrário, leia a seção **Estado atual** abaixo e consulte o histórico do git (`git log --oneline`).

---

## 1. Regra de ouro: escopo

Este projeto é refatorado em PRs **de escopo estreito e disciplinado**. O humano é rígido sobre isso.

**NUNCA, em nenhuma hipótese, faça dentro de um PR:**
- Mais de uma coisa (ex: PR "trocar persistência" não toca em UI).
- "Melhoria oportunista" não combinada (renomear variável aleatória, arrumar lint pré-existente que não é relacionado, mudar ordem de imports só porque está feio).
- Mudanças cosméticas (withOpacity → withValues, const constructors em trechos não-tocados) — essas ficam para um PR cosmético dedicado.
- Antecipar o próximo PR. Se o PR atual é #8, não mexa em nada que pertença ao #9/#10.
- Deletar código legado no mesmo PR que introduz o substituto. Primeiro introduz → estabiliza → PR posterior remove.

Se você achar que precisa fazer algo fora de escopo, **pare e pergunte ao humano**. Não comece.

---

## 2. Protocolo multi-agente

Mais de uma IA pode tocar este repositório ao longo do tempo (Claude Code, Codex, etc). Elas **não conversam em tempo real** — coordenam via:

1. **Git** — fonte única de verdade. Cada agente lê `git log`, `git status`, `git diff` no início da sessão.
2. **Este arquivo (`AGENTS.md`)** — contém o estado/regras. Alterações aqui são commits como qualquer outro.
3. **Seção `## 10. Handoff Log`** — append-only. **Todo agente, ao final de uma sessão significativa, adiciona uma entrada** com: data, identificação (ex: "Claude Code"), o que fez, branch ativa, próximo passo sugerido.
4. **Mensagens de commit** — verbosas, explicam o "porquê". Outro agente precisa entender olhando só o log.

### Quando você (agente) entrar em uma sessão nova:

1. `git status` e `git log --oneline -20` — entenda onde está.
2. Leia este arquivo inteiro.
3. Leia a **última entrada** do Handoff Log.
4. Se houver branch feature ativa (não `main`), entenda o que está em progresso antes de criar branch nova.
5. Só então comece.

### Quando você terminar uma sessão:

1. Commite o que fez (nunca deixe mudanças não commitadas de sessão anterior para outro agente limpar).
2. Adicione entrada no Handoff Log.
3. Se o trabalho não está completo, **deixe claro o próximo passo concreto** — caminho de arquivo, nome de função, comando a rodar.

---

## 3. Regras de git

- **Sempre criar branch feature**: `refactor/prN-slug` (ex: `refactor/pr8-firestore-uuid`).
- **Nunca commit direto em `main`**.
- **Merge sempre com `--no-ff`** para preservar a topologia. Mensagem de merge: `Merge PR #N: <mesmo título do commit>`.
- **Nunca `push --force`** em `main`. Nunca `reset --hard` sem confirmar com humano.
- **Nunca `git add -A` ou `git add .`** — adicione arquivos por nome. Evita vazar `.env`, chaves, binários grandes, `google-services.json` alterado sem querer.
- **Nunca `--no-verify`** em commits.
- **Convenção de mensagem de commit** (copia o estilo dos commits existentes):

  ```
  <type>(<escopo>): <resumo em uma linha, imperativo>

  <parágrafo explicando o porquê — não o quê>

  - <arquivo>: <o que mudou>
  - <arquivo>: <o que mudou>

  <notas sobre escopo preservado, compatibilidade, testes>
  ```

  Exemplos de `type`: `refactor`, `feat`, `fix`, `test`, `docs`, `chore`, `build`.

- **Co-author**: se for IA da Anthropic, adicione `Co-Authored-By: Claude <noreply@anthropic.com>` (ou versão específica) no rodapé do commit. Se for outra ferramenta, use a convenção dela. Humano nunca é co-author sem pedir.

- **Branches antigas não são deletadas** depois de merge. Ficam como histórico. Não faça limpeza de branches sem autorização.

---

## 4. Convenções de código

- **Linguagem**: classes/arquivos em inglês. Strings de UI e doc-comments em português BR (é uma app brasileira).
- **Imutabilidade**: entidades de domínio são `final` em tudo. `copyWith` para alterar.
- **Igualdade por id** onde há id (`Person`, `TabletIdentity`).
- **Enums serializados por `.name` (`.key`)**, nunca por `index`.
- **Sempre adicionar testes** para código novo. Testes ficam em `test/<mirror do path em lib/>`.
- **`flutter analyze`** precisa continuar sem erros novos (warns pré-existentes podem ficar — veja seção 6).
- **`flutter test`** precisa continuar verde (hoje 33/33).

### Padrão de migração (MUITO IMPORTANTE)

Qualquer migração de formato local (Hive, SharedPreferences) **deve**:
1. Ter flag de idempotência em `SharedPreferences` com nome versionado (ex: `people_repo_migrated_v1`).
2. Ser **idempotente por duas razões** (flag + check de colisão) — belt-and-suspenders contra flag removida manualmente.
3. **Preservar o formato legado** por pelo menos 1 release. Não deletar no mesmo PR que cria o novo.
4. Ter testes cobrindo: fresh install, migração com dados, segunda execução (no-op), flag removida + dados já presentes no novo formato.

Referência viva: `lib/infrastructure/persistence/hive/hive_person_repository.dart` + teste correspondente.

### Não-faça

- Não use `name` de uma pessoa como chave de nada novo (ver seção 8 — dívida em transição).
- Não rode `Hive.init(...)` em código de produção — use `Hive.initFlutter()`. O parâmetro `hiveHomeDir` do `HivePersonRepository.initialize()` é **hook de teste**, não chamar com valor em produção.
- Não mexa no threshold `0.45` de cosine distance sem um PR dedicado (#10).
- Não mexa no pipeline `AccessScreen._processFrame` sem PR #9.
- Não altere `google-services.json` — ele precisa ser atualizado manualmente no Firebase Console (ver seção 8).

---

## 5. Testes — como rodar

```bash
flutter pub get
flutter analyze                              # não deve adicionar erro novo
flutter test                                 # deve continuar 33/33 verde
flutter test test/<path>                     # arquivo específico
flutter run --flavor admin -t lib/main_admin.dart
flutter run --flavor porta -t lib/main_porta.dart
```

### Padrão para testes que tocam Hive

```dart
late Directory tempDir;
setUp(() async {
  tempDir = await Directory.systemTemp.createTemp('faceaccess_test_');
  SharedPreferences.setMockInitialValues({});
  await Hive.close();
});
tearDown(() async {
  await Hive.close();
  if (await tempDir.exists()) await tempDir.delete(recursive: true);
});
// ... usa repo.initialize(hiveHomeDir: tempDir.path)
```

Stubs de UUID em teste: implementam `Uuid` via `noSuchMethod` (ver `_FixedUuid` / `_SequentialUuid` em `test/infrastructure/persistence/hive/hive_person_repository_test.dart`).

---

## 6. Lints e dívida conhecida

`flutter analyze` hoje reporta ~35 infos/warns **pré-existentes**. NÃO corrija dentro de outro PR. A lista:

- `withOpacity` deprecated em várias telas → migrar para `.withValues()` em PR cosmético dedicado.
- `_processFrame` unused em `access_screen.dart` → revisar junto com PR #9 (pipeline de reconhecimento).
- `body_might_complete_normally_catch_error` em `register_screen.dart:176` → pré-existente.
- Alguns `prefer_const_constructors` e `curly_braces_in_flow_control_structures` → cosmético.
- `UserRole` depende de Flutter Material (cores/ícones). Deveria ser data-only no domain. Dívida assumida.

---

## 7. Estado atual (atualize quando mergear um PR)

**Último PR merged em `main`:** PR #7 (`fda0d1d` — Merge PR #7: refactor(persistence): replace FaceDatabase with HivePersonRepository and UUID-based people storage).

**Branches de feature existentes (não apagar):**
- `refactor/pr1-riverpod-scaffold`
- `refactor/pr2-domain-foundation`
- `refactor/pr3-composition-root`
- `refactor/pr4-auth-migration`
- `refactor/pr5-user-profile-rename`
- `refactor/pr6-tablet-assignment`
- `refactor/pr6.5-flavors`
- `refactor/pr7-person-repo`

**Testes:** 33 passando.

**Próximo PR planejado: PR #8** — `refactor(remote): migrate Firestore to UUID-keyed documents with bidirectional sync`.

### Escopo do PR #8 (resumo — ver handoff completo para detalhes)

Hoje o Firestore ainda é keyed por `name` — o Hive local já foi para UUID no PR #7, então há uma "ponte" temporária em `app.dart` que faz lookup name→Person para preservar UUIDs. O PR #8 elimina essa ponte.

**Fazer:**
1. Coleção `people` keyed por `Person.id` (UUID). Fields: `id`, `name`, `roleKey`, `locationIds: array<String>` (substitui `allowedUnits`), `embeddings: map<String,List<double>>`, `createdAt: int`, `updatedAt: serverTimestamp`.
2. Migração Firestore idempotente (flag em doc `/_meta/migrations` com `{people_v1_to_v2: true}`). Docs antigos **não são deletados** — marcados com `migrated: true`.
3. Reescrever `FirebaseDatabase`: `savePerson(Person)`, `deletePerson(String id)`, `loadAll({String? locationId}) → Map<String, Person>`.
4. Remover lookup `byName` em `lib/app/app.dart:_startFirestoreSync`. Sync vira match direto por id.
5. Remover DTO `PersonRecord` de `firebase_database.dart` (era ponte do PR #7).
6. Sync bidirecional com resolução last-write-wins por `updatedAt`.
7. Atualizar call sites: `register_screen.dart`, `people_list_screen.dart`, `app.dart`.
8. Testes novos em `test/infrastructure/persistence/firebase/` (considerar `fake_cloud_firestore` do pub.dev).

**Não fazer no PR #8:**
- Deletar box Hive legada `face_embeddings_v2` (ainda é rollback local — PR posterior, depois de estabilidade).
- Qualquer mudança em reconhecimento / câmera / matching (PR #9/#10).
- UI nova.
- Correção de lints não-relacionados.

**Critérios de aceitação:**
- `flutter test` 33/33 + novos testes do PR #8 verdes.
- `flutter analyze` sem erro novo.
- Renomear pessoa no admin não quebra identidade (hoje = cria doc duplicado).
- Sync offline→online→offline converge sem duplicar pessoas.

---

## 8. Contexto que você PRECISA saber antes de editar

1. **`name` ≠ identidade**. Nome é mutável e colide (homônimos). Chave primária é UUID em tudo que é código novo. Código legado ainda em transição: `FirebaseDatabase` (até PR #8).

2. **Firestore não aceita array aninhado.** Por isso `embeddings` é `Map<String, List<double>>` com chaves `"0"`, `"1"`, …  Ver `_parseEmbeddings()` em `firebase_database.dart`. **Preservar esse formato no PR #8.**

3. **`UserRole` vs `OperatorRole`** são distintos:
   - `UserRole` = cargo da pessoa cadastrada (admin/diretor/gerente/supervisor/lider/manutentor/operador). Aparece no crachá.
   - `OperatorRole` = quem opera o tablet (admin/porta). Só dois valores.
   - Nunca misturar.

4. **`TabletIdentity.id` é UUID local gerado no primeiro boot** — não é serial do tablet. Se o app for desinstalado, muda.

5. **`locationIds` é `Set<String>`** (pessoa pode ter acesso a N unidades). `TabletAssignment.locationId` é `String?` (tablet está em uma unidade só).

6. **Offline é cenário normal.** `FirebaseDatabase.loadAll()` falha silenciosamente quando offline. UI sempre pressupõe que o remoto pode estar fora.

7. **`google-services.json` atualmente só conhece `com.example.faceaccess`.** Builds debug funcionam. Builds release dos flavors `.admin`/`.porta` **vão falhar** até os package names serem registrados manualmente no Firebase Console. Essa é uma ação **humana**, não faça sozinho.

8. **Não há keystore real de release** — o `build.gradle` usa `signingConfig signingConfigs.debug` para release. Trocar por keystore real é ação humana pendente.

9. **Threshold 0.45 é calibrado para FaceNet 512-d.** Alterar = PR #10 com medições antes/depois, dados reais das duas unidades.

10. **Idioma:**
    - Código e nomes: inglês.
    - UI, mensagens de erro visíveis, doc-comments: português BR.
    - Commit messages e PR titles: inglês (convenção do projeto).
    - Este arquivo e `docs/HANDOFF.md`: português (humano brasileiro lê junto).

---

## 9. Arquivos-referência ao abrir o projeto

| Primeiro a ler | Por quê |
|---|---|
| `AGENTS.md` (este) | Protocolo e estado |
| `docs/HANDOFF.md` (se existir) | Resumo técnico completo |
| `lib/app/bootstrap.dart` | Ponto de entrada real |
| `lib/app/app.dart` | Composition + decisão de qual tela |
| `lib/app/providers/repository_providers.dart` | Onde os 3 repositórios são montados |
| `lib/infrastructure/persistence/hive/hive_person_repository.dart` | Exemplo vivo do padrão de migração |
| `test/infrastructure/persistence/hive/hive_person_repository_test.dart` | Exemplo de padrão de teste |
| `lib/application/use_cases/evaluate_access_use_case.dart` | Onde PR #9/#10 vão tocar |
| `android/app/build.gradle` (`productFlavors`) | Config dos dois APKs |

---

## 10. Handoff Log (append-only)

Formato de cada entrada:

```
### YYYY-MM-DD — <Agente> — <Branch ativa>
**Fiz:** ...
**Deixei em:** <commit sha> (branch <nome>, estado: clean / dirty / WIP)
**Testes:** X/Y passando
**Próximo passo concreto:** ...
**Gotchas descobertas:** ...
```

---

### 2026-04-21 — Codex (GPT-5) — `refactor/pr8-firestore-uuid`
**Fiz:** Reescrevi `lib/infrastructure/firebase_database.dart` para o schema remoto keyed por UUID (`id`, `roleKey`, `locationIds`, `createdAt`, `updatedAt`), removi o DTO `PersonRecord`, adicionei migração remota idempotente com flag em `/_meta/migrations`, preservação do doc legado via `migrated: true`, sync bidirecional em `FirebaseDatabase.synchronize(...)` com resolução last-write-wins por `updatedAt` e bridge de compatibilidade para evitar duplicação quando houver mismatch legado por nome. Atualizei `lib/app/app.dart` para delegar o sync ao `FirebaseDatabase`, além dos call sites de cadastro/exclusão em `register_screen.dart` e `people_list_screen.dart` para operar por `Person.id`. Adicionei `fake_cloud_firestore` e uma suíte nova em `test/infrastructure/persistence/firebase/firebase_database_test.dart`.
**Deixei em:** branch `refactor/pr8-firestore-uuid` (WIP, pronto para commit). Worktree com mudanças em `lib/app/app.dart`, `lib/infrastructure/firebase_database.dart`, `lib/presentation/register_screen.dart`, `lib/presentation/people_list_screen.dart`, `pubspec.yaml`, `pubspec.lock`, novo diretório `test/infrastructure/persistence/firebase/` e este `AGENTS.md`.
**Testes:** 39/39 passando. `flutter analyze`: 35 infos/warns pré-existentes, 0 erros novos.
**Próximo passo concreto:** revisar o diff final do PR #8, commitar com mensagem `refactor(remote): migrate Firestore to UUID-keyed documents with bidirectional sync` e então abrir a revisão. Se aparecer qualquer dúvida funcional, os pontos mais sensíveis para sanity-check são `FirebaseDatabase.migrateRemoteIfNeeded()`, `FirebaseDatabase.synchronize()` e a query `locationIds` em `loadAll()`.
**Gotchas descobertas:**
- Sem um `updatedAt` local no domínio, o sync usa `Person.createdAt` como carimbo local mais recente; isso cobre o estado atual do app (create/delete), mas uma futura UI de edição pode justificar promover `updatedAt` para o modelo local.
- Para docs legados sem match local, a migração usa UUID determinístico por nome (`uuid.v5`) para reduzir risco de duplicação entre tablets durante a janela de rollout.
- `flutter analyze` voltou exatamente ao baseline conhecido de 35 avisos; os avisos do PR foram zerados.

### 2026-04-21 — Claude Code — `main`
**Fiz:** PR #7 finalizado e mergeado em `main` (commit `fda0d1d`). `HivePersonRepository` criado, `FaceDatabase` e `FaceDatabaseRepository` removidos, `PersonRecord` inlinado em `firebase_database.dart`, sync Firestore em `app.dart` atualizado para preservar UUIDs via lookup name→Person. 8 testes novos. Depois do merge, criado este `AGENTS.md`.
**Deixei em:** `main @ fda0d1d` (clean). Branch `refactor/pr7-person-repo` preservada.
**Testes:** 33/33 passando. `flutter analyze`: 35 infos/warns pré-existentes, 0 erros.
**Próximo passo concreto:** Abrir branch `refactor/pr8-firestore-uuid` a partir de `main` e seguir o escopo do PR #8 na seção 7. Primeiro arquivo a reescrever: `lib/infrastructure/firebase_database.dart`. Segundo: remover lookup `byName` em `lib/app/app.dart:_startFirestoreSync` (linhas 71–116 aproximadamente). Considerar adicionar `fake_cloud_firestore` como dev_dependency para os novos testes.
**Gotchas descobertas:**
- `path_provider_platform_interface` não é dependência direta — por isso o `hiveHomeDir` hook em `initialize()` é necessário para bypassar `path_provider` em testes.
- `google-services.json` desatualizado para os novos flavors — blocker de build release mas não de debug nem de testes.
- OneDrive: o projeto vive em `C:\Users\thiag\OneDrive\Documentos\FaceAcess`. Se outra IA não achar, é caminho/sync pausado.

---

<!-- Próxima entrada vai aqui. Copie o template acima. Ordem reverso-cronológica (mais recente no topo). -->

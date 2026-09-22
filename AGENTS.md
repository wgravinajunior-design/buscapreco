# Diretrizes do Projeto BuscaPreço (Totem Flutter)

## Regra Obrigatória: Versionamento e Release a Cada Correção ou Melhoria

**SEMPRE** que você fizer qualquer correção de bug, ajuste ou melhoria de funcionalidade neste projeto, você DEVE gerar uma nova versão e publicá-la no Git/GitHub. Isso é essencial para que os totens em produção detectem a atualização e se mantenham sincronizados.

### Checklist Obrigatório para Toda Modificação:

1. **Incrementar Versão (SemVer):**
   - **Correções de bugs / ajustes:** Incrementar PATCH (ex: `1.0.0` -> `1.0.1`, `1.0.1` -> `1.0.2`).
   - **Novas funcionalidades / melhorias significativas:** Incrementar MINOR (ex: `1.0.x` -> `1.1.0`).

2. **Sincronizar Arquivos de Versão:**
   - `pubspec.yaml`: `version: X.Y.Z+N` (incrementar build number).
   - `lib/config/app_version.dart`:
     ```dart
     static const String version = 'X.Y.Z';
     static const int buildNumber = N;
     ```

3. **Commit e Tag Git:**
   - Criar commit no branch `master` com descrição clara das alterações.
   - Criar tag anotada: `git tag -a vX.Y.Z -m "vX.Y.Z: descrição das correções/melhorias"`

4. **Enviar para o GitHub:**
   - `git push origin master`
   - `git push origin vX.Y.Z`

5. **Publicar Release no GitHub:**
   - Usar GitHub CLI (`gh release create vX.Y.Z ...`) com notas da versão e APK anexado, ou executar o script `publicar_versao.ps1`.
   - Repositório oficial: `https://github.com/wgravinajunior-design/buscapreco`

6. **Integridade do Totem:**
   - Manter o foco contínuo do leitor de código de barras no totem (`BarcodeKeyboard`).
   - Manter compatibilidade com consultas em Firebird 5 direto pela rede local.

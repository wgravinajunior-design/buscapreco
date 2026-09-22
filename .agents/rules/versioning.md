---
description: Regra de versionamento e publicação automática de release no GitHub
globs: ["**/*"]
---

# Regra de Versionamento e Atualização Automática

Sempre que qualquer correção, bug fix, ajuste ou melhoria for realizada no projeto BuscaPreço:

1. Incrementar a versão no `pubspec.yaml` (`version: X.Y.Z+N`) e no `lib/config/app_version.dart` (`version = 'X.Y.Z'`, `buildNumber = N`).
2. Criar commit descritivo no Git.
3. Criar tag anotada `vX.Y.Z` (`git tag -a vX.Y.Z -m "vX.Y.Z: ..."`) e enviar para o GitHub (`git push origin master` e `git push origin vX.Y.Z`).
4. Publicar o Release no GitHub (`gh release create vX.Y.Z ...`) anexando o APK ou chamando `publicar_versao.ps1`.
5. Os totens dependem das tags e releases no GitHub para o sistema de auto-atualização em produção.

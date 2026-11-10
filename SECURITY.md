# Security Policy / セキュリティ

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through
GitHub's [private vulnerability reporting](https://github.com/takumi8420/Macorn/security/advisories/new)
(the "Report a vulnerability" button on the Security tab).

Macorn can replace itself with a new version (Macorn › Check for Updates…), so issues in the
update path are especially important. The updater only installs an app whose signature is valid,
issued by Apple, and belongs to the same Developer ID team, and that has the same bundle ID and the
announced version (`Macorn/App/UpdateInstaller.swift`).

Only the latest release is supported. Fixes are shipped as a new version.

## 脆弱性の報告

セキュリティに関わる問題は、**公開の Issue には書かず**、GitHub の
[非公開の脆弱性報告](https://github.com/takumi8420/Macorn/security/advisories/new)
（Security タブの「Report a vulnerability」）から知らせてください。

Macorn は自分で新しい版に入れ替える仕組み（Macorn › アップデートを確認…）を持っているため、
更新の経路に関わる問題は特に重く扱います。入れ替えるのは、Apple が発行した同じ Developer ID のチームの
正しい署名があり、同じアプリ ID・知らされた版のアプリだけです（`Macorn/App/UpdateInstaller.swift`）。

直すのは最新の版だけです。修正は新しい版として出します。

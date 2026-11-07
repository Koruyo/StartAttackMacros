# Veröffentlichen auf CurseForge

## 1. GitHub

```bash
gh auth login -h github.com
```

Danach legt Claude das private Repo an und pusht es. GitHub Actions läuft auch bei privaten Repos
(2.000 Freiminuten pro Monat, ein Release braucht etwa 1 Minute).

## 2. CurseForge-Projekt anlegen

1. Auf <https://authors.curseforge.com> → **Create Project** → *World of Warcraft* → *Addons*.
2. Diese Felder ausfüllen:

| Feld | Inhalt |
|---|---|
| Name | `StartAttack Macros` |
| Summary | Text aus [`curseforge-summary.txt`](curseforge-summary.txt) |
| Description | Inhalt von [`curseforge-description.md`](curseforge-description.md) (Editor auf **Markdown** stellen) |
| Logo / Avatar | [`media/logo.png`](../media/logo.png) (512×512) |
| Primary Category | Action Bars |
| Weitere Kategorien | Combat, Class |
| License | MIT |
| Source / Issues | leer lassen (das Repo ist privat) |

3. **Banner:** Lade [`media/banner.png`](../media/banner.png) unter *Images* hoch, kopier die
   Bild-URL und ersetz damit `BANNER-URL` in der ersten Zeile der Beschreibung. Ein Link auf
   GitHub geht nicht, weil das Repo privat ist.
4. **Screenshots** unter *Images* hochladen. Empfohlen: das Fenster, die Optionsseite und eine
   umgewandelte Aktionsleiste. Die musst du im Spiel machen (Druck-Taste, landen in `Screenshots/`).

## 3. Automatische Uploads einrichten (optional, empfohlen)

1. Die **Project ID** steht rechts auf der CurseForge-Projektseite. Trag sie in
   `StartAttackMacros.toc` ein:
   ```
   ## X-Curse-Project-ID: 123456
   ```
2. Auf <https://authors.curseforge.com/account/api-tokens> einen **API-Token** erstellen.
3. Auf GitHub: Repo → *Settings* → *Secrets and variables* → *Actions* → **New secret**
   Name: `CF_API_KEY`, Wert: der Token.
4. Neue Version veröffentlichen:
   ```bash
   git tag v1.2.0
   git push --tags
   ```
   GitHub baut dann das Zip und lädt es auf CurseForge und unter GitHub *Releases* hoch.

> **Hinweis WoW Forever:** Der Packager leitet die Spielversion aus `## Interface:` ab. Falls
> CurseForge die Forever-Version (16001) noch nicht kennt, schlägt der Upload fehl. Dann lade das
> Zip aus GitHub *Releases* manuell auf CurseForge hoch und wähl die Version dort aus.

## Neue Version

1. Änderungen oben in `CHANGELOG.md` eintragen.
2. Committen, dann `git tag vX.Y.Z` und `git push --tags`.

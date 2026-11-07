![StartAttack Macros](BANNER-URL)

## Never stand there doing nothing again

In Classic, using an ability does **not** always start your auto-attack, and that costs you a
lot of damage. The usual fix is to write a `/startattack` macro for every ability by hand.

**StartAttack Macros does it for you, in one click.**

### Features

- **Spellbook window**: all your attack abilities in one place. Click or drag one and its
  `/startattack` macro is ready for your action bar.
- **One-click conversion**: replaces every attack ability on your action bars with its macro,
  in the same slot.
- **Smart filtering**: only attack abilities. Ranks are merged (always the highest rank), and
  Auto Attack / Shoot / Auto Shot are skipped.
- **Macro tracking**: check marks for existing macros and a free-slot counter.
- **Minimap button**, **Addon Compartment** entry and a full **options panel**.
- **Lightweight**: no libraries, no dependencies.
- **10 languages**: English, Deutsch, Français, Español, Italiano, Português, Русский, 한국어, 简体中文, 繁體中文

### Commands

| Command | Action |
|---|---|
| `/sam` | Open / close the window |
| `/sam convert` | Convert all attacks on your action bars |
| `/sam <spell name>` | Put the macro for one spell on your cursor |
| `/sam options` | Open the options |
| `/sam minimap` | Show / hide the minimap button |

### Good to know

Blizzard protects `StartAttack()`, so no addon is allowed to start your attack on its own.
Macros are the only allowed way, and this addon builds and places them for you. Macros are named
`+SpellName` and use character-specific slots first. Nothing can be changed in combat.

---

## Deutsch

**Jede Fähigkeit startet automatisch deinen Autoangriff.** Das Addon erstellt `/startattack`-Makros
für deine Angriffsfähigkeiten und setzt sie auf Wunsch direkt in deine Aktionsleisten.
`/sam` öffnet das Fenster, und `/sam convert` wandelt alle Leisten um.

---

Bugs & ideas: please leave a comment on this page.

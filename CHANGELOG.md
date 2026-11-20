# Changelog

## v1.5.0
- New field "Lines after /cast": add your own macro lines at the end of the macro. It has its
  own tick box and is saved per character
- All four text fields now look the same and have the same size; long conditions wrap onto a
  second line instead of being cut off

## v1.4.0
- Fixed: long spell names with non-Latin letters (Russian, Korean, Chinese, also umlauts and
  accents) were cut in the middle of a letter. The broken macro name could make the server drop
  macros on the next login. Names are now cut at a full letter, and macros that already have a
  broken name are renamed automatically
- New field "Lines before /startattack": add your own macro lines, for example `/petattack`,
  between `#showtooltip` and `/startattack`. It has its own tick box and is saved per character
- Broker support: the addon shows up as a launcher in Titan Panel, ChocolateBar and other
  LibDataBroker displays (left-click opens the window, right-click the options)
- A text you are still typing is now applied when you click an ability, a tick box or the
  convert button

## v1.3.1
- "Convert all attacks on your action bars" now also updates the macros the addon already
  created, so they pick up the current text fields and tick boxes
- A yellow question mark marks abilities whose macro does not match the current texts yet;
  the green check mark now means the macro is up to date

## v1.3.0
- New fields "Add after /startattack" and "Add after /cast" in the window: insert your own
  macro conditions, for example `[harm,nodead]` and `[@mouseover,harm,nodead][]`, into every macro
- Tick box next to each field to create individual macros with or without the text
- Changing a text updates the macros that already contain it

## v1.2.0
- Localized for every Classic client language: English, Deutsch, Français, Español, Italiano,
  Português (BR), Русский, 한국어, 简体中文, 繁體中文
- Addon icon, minimap button and Addon Compartment entry
- Options panel (Esc → Options → AddOns) with buttons and settings
- Window shows a check mark for abilities that already have a macro
- Macro slot counter
- Fixed: `/sam` did not open the window the first time

## v1.0.0
- First release: create `/startattack` macros from the spellbook
- Convert all attack abilities on your action bars in one click

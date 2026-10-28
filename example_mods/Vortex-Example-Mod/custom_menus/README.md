# custom menus

this folder changes how the menus look, no code needed. turn it on in the developer menu (press 7 on the main menu) > Menu Editor > Custom Theme. if `"autoApply"` is true it turns on by itself when the player hasnt picked a theme yet.

- `menu.json` - the settings
- `assets/` - pictures (png) and fonts (ttf/otf)
- `animations/` - animated pictures, name.png + name.xml (sparrow sheet like characters)

the menu editor can change the main settings and shows a preview. if menu.json has a mistake the normal theme gets used and the error shows up in the menu editor and in `vortex_script_log.txt`.

## menu.json

everything is optional, if you leave something out it uses the default.

- `format` - always 1
- `name`, `author` - shown in the menu editor
- `autoApply` - true = used until the player picks a theme
- `font` - a ttf/otf in assets/, or one of the game fonts like `vcr.ttf` or `pixel-latin.ttf`
- `colors` - panelFill, panelBorder, panelBorderSelected, accent, text, textDim, primary, secondary, tertiary as `"#RRGGBB"`. buttons go through primary, accent, secondary, tertiary
- `background` - `{"type": "cosmic"}`, `{"type": "color", "color": "#101020"}`, `{"type": "gradient", "colors": ["#1A0F3D", "#05040D"]}` or `{"type": "image", "image": "bg.png"}`. images can also have `"scroll": [20, 0]` (pixels per second) and `"alpha": 0.8`. you can put an `"animation"` on top of any background (see below). cosmic can turn the rings off with `"rings": false`
- `animations` - `"intro"`: "slide", "fade" or "none", `"speed"`: 1 is normal
- `transitions` - `"type"`: "fade" or "none", `"duration"` in seconds
- `freeplay` - title, showInfoPanel (false puts the song list in the middle), background
- `storyMode` - title, background
- `developerMenu` - title, background
- `chartEditor` - background colour, grid and gridOther (2 colours each)
- `mainMenu` - see below

### mainMenu

- `title`, `subtitle` - the big text and the line under it
- `logo` - a picture in assets/ (`"logo.png"`) or an animation: `{"file": "logo", "prefix": "logo bumpin", "fps": 24, "x": 40, "y": 10, "scale": 0.8}`
- `buttons` - x, y, spacing, width and align ("left", "center", "right")
- `labels` - different button text, like `{"story_mode": "CAMPAIGN", "freeplay": "SONGS"}`
- `icons` - a picture on a button, like `{"story_mode": "icons/story.png"}`
- `showInfoPanel` - false hides the panel on the right
- `infoText` - different text in that panel, like `{"mods": "addons for this mod"}`
- `navigation` - `"wrap": false` stops at the top/bottom, `"mouse": false` turns the mouse off
- `showVersion` - false hides the version text
- `background` - a background just for the main menu

the option names are story_mode, freeplay, mods, credits, achievements and options.

### animations

put `star.png` + `star.xml` in animations/ and use it like `{"file": "star", "prefix": "star spin", "fps": 24, "x": 1000, "y": 40, "scale": 1, "loop": true}`

### what it cant do

you keep all the menu options, keys and the same layout (buttons on the left, panels on the right). for a totally different menu use a state script (`states/MainMenuState.lua`) or a custom state.

# ADR 09b — In-Game IDE: UI Architecture

Companion to `09_BEHAVIOR_AUTHORING_PLATFORM.md`. Phase 1 built the headless platform; this
governs the surface a human touches.

---

## 1. What we are actually building on

`core.menu.window` is an **ImGui-style immediate-mode API**, not a widget toolkit. That single fact
determines everything below.

Verified available (`docs/SylvannasAPI/dev/api/ui-custom.md`, `guides/custom-ui.md`):

| Capability | API |
| --- | --- |
| Independent windows | `core.menu.window(id)`, `set_initial_size/position`, `set_visibility` |
| Frame | `window:begin(resize_flags, has_cross, bg, border, cross_style, fn)` |
| Modal | `window:begin_popup(bg, border, size, pos, …, fn)` |
| Grouping | `window:begin_group(fn)` |
| **Hover state** | `window:is_mouse_hovering_rect(v1, v2)` |
| **Click regions** | `window:is_rect_clicked(v1, v2)` |
| Drawing | `render_rect`, `render_rect_filled`, `render_rect_filled_multicolor`, `render_circle(_filled)`, `render_triangle_filled_multicolor`, `render_bezier_quadratic/cubic`, `render_text` |
| Layout | `add_menu_element_pos_offset`, `get_current_context_dynamic_drawing_offset`, `add_artificial_item_bounds`, `get_text_centered_x_pos`, `add_separator` |
| Motion | `window:animate_widget(id, from, to, a0, a1, a_speed, move_speed, once)` → `{current_position, alpha}` |
| Stock widgets | `text_input`, `combobox`, `combobox_reorderable`, `tree_node`, `checkbox`, `slider_int/float`, `button`, `color_picker`, `keybind`, `label`, `separator` |

Requires `common/color`, `common/geometry/vector_2`, `common/enums`.

**Hover + click regions + filled rects is the whole game.** Anything the stock widgets cannot do,
we draw ourselves and hit-test by rectangle. That is how this gets a modern look rather than a
1990s options dialog.

---

## 2. Non-negotiables

### 2.1 State/render split

IDE state is a **plain Lua model**, offline-testable, with **zero** decision logic in any render
function. The render layer is a pure projection of the model.

This is already the repo's proven pattern — `modules/questing/runner_state.lua` is a pure
view-model with offline tests and `runner_ui.lua` is a thin projection of it. The IDE follows it
because code inside a render callback **cannot be tested outside the game**, and an editor whose
logic is untestable is an editor nobody can safely change.

### 2.2 Creation in tick, rendering in render

Sylvannas forbids creating windows and menu elements inside a render callback. Every
`core.menu.*` object is constructed at module scope or in the tick callback; render only calls
`:render()` / `:begin()`. `sentinel/main.lua` already does this correctly for the existing editor
scaffold (`ensure_frames_created` from `register_on_update_callback`) — extend that, do not invent
a second mechanism.

Getting this wrong fails at runtime and passes every offline test.

### 2.3 Persistence is ghost sliders or nothing

Menu elements are **the only** resource that survives an injection. Window position, size, active
panel, and last-opened campaign persist through hidden `slider_int` elements, per the pattern in
`guides/custom-ui.md` §Basics-1 Case 2.

There is no other mechanism. `core.write_data_file` persists *documents*, not UI state, and reading
a file every frame to restore layout is not acceptable.

### 2.4 Frame budget

`register_on_render_window_callback` runs **every frame**. No HTTP, no file IO, no full-corpus
scans inside it. Every network result is fetched asynchronously into the model and rendered from
cache. A search request fires on input change with debounce, never per frame.

---

## 3. Design system

`sentinel/ui/theme.lua` is the single source of visual truth. Panels import it; nothing hardcodes a
color or a spacing number. This is what makes five panels built by five hands look like one
product.

It owns:

- **Palette** — surface, surface-raised, border, text-primary, text-muted, accent, and the four
  semantic states (success / warning / danger / info). Defined once as `color` values.
- **Elevation** — background and border pairs for base / raised / overlay, so a popup is
  distinguishable from the panel behind it without a drop shadow we cannot draw.
- **Spacing scale** — a single 4px-based ramp. Arbitrary pixel offsets are the reason immediate-mode
  UIs drift into visual noise.
- **Interaction alphas** — resting / hover / active. The guide's own idiom is alpha-shift on hover
  (`alpha = 120` → `255`); centralizing it means every clickable thing in the IDE responds
  identically.
- **Type scale** — which `font_id` means title, body, caption.
- **Hit-target minimum.** A game overlay is used with a mouse that is also steering a character;
  targets are larger and contrast higher than a desktop app would need.

### 3.1 Widget library

`sentinel/ui/widgets.lua` — composed from rects, hover tests, and click tests:

`button`, `icon_button`, `list_row` (selected / hover / disabled), `search_field`
(wrapping `text_input`), `chip`, `toolbar`, `section_header`, `empty_state`, `toast`,
`badge`, `split_pane`.

Each takes an explicit bounds rect and returns whether it was activated. Stateless by
construction — state lives in the model. Stock `core.menu.*` widgets are used wherever they already
fit (checkbox, slider, combobox, text_input); we do not re-implement what exists.

---

## 4. Window topology

```
┌─ Sentinel (main window) ─────────────────────────────┐
│  Runner │ Explorer │ Graph │ Properties │ Database   │   ← panel switcher
├──────────────────────────────────────────────────────┤
│                                                      │
│                  active panel body                   │
│                                                      │
└──────────────────────────────────────────────────────┘

Detachable secondary windows: Database Browser, Map, Simulator
```

One main window with a panel switcher, plus **detachable** secondaries. `window:begin` is
per-window, so a detached Database Browser can sit beside the editor rather than replacing it —
which is the difference between looking something up and losing your place.

The **Runner** panel is first in the tab order because the bot running correctly matters more often
than authoring does, and `runner_state.lua` already supplies its entire view-model.

---

## 5. UX rules for an in-game editor

These are chosen for this context, not imported wholesale from desktop design.

1. **Never modal unless destructive.** The player may need to react to the game. Popups are for
   confirming deletion, nothing else.
2. **Escape closes, a keybind toggles.** Hands stay near movement keys. `core.menu.keybind` exists.
3. **Validate continuously, not on save.** The resolver already returns diagnostics; surface them
   against the offending node as they change. An author should never press a button to find out
   they were wrong.
4. **Every interactive region reports hover.** Immediate-mode UIs feel dead without it, and we get
   it for one `is_mouse_hovering_rect` call.
5. **Empty states instruct.** "No campaign open — record one, or open an existing route" beats a
   blank pane, especially while the corpus is empty.
6. **Show the resolved value beside the intent.** The author writes `Deputy Willem`; the panel shows
   `npc:823 · (-8933.5, -136.5, 83.4)`. This is what makes coordinates stop being something anyone
   types while staying inspectable when a route misbehaves.
7. **Motion only to explain.** `animate_widget` exists; use it for panel transitions and toasts, not
   decoration. Anything animating during combat is a bug.

---

## 6. Work units

Ownership is disjoint by file, as in phase 1.

| # | Unit | Owns | Depends on |
| --- | --- | --- | --- |
| U1 | Theme + widget library | `sentinel/ui/theme.lua`, `sentinel/ui/widgets.lua` | — |
| U2 | IDE shell: window, panel switcher, layout persistence | `sentinel/ui/shell.lua`, `main.lua` wiring | U1 |
| U3 | Database browser | `sentinel/ui/panels/database.lua` | U1 |
| U4 | Explorer + schema-driven Properties | `sentinel/ui/panels/{explorer,properties}.lua` | U1 |
| U5 | Runner panel | `sentinel/ui/panels/runner.lua` | U1 |
| U6 | Graph canvas | `sentinel/ui/panels/graph.lua` | U1, U2 |
| U7 | Map canvas | `sentinel/ui/panels/map.lua` | U1, U2 |

**U4 carries the platform's enforcement point**: the Properties panel renders from the resolver's
`Field` schema, fetched over HTTP. Hand-coding a panel per task type builds a quest editor
permanently, whatever this document is called (ADR 09 §4).

---

## 7. Testing an immediate-mode UI

Every panel splits into a `*_state.lua` view-model and a render function. The view-model is
offline-tested exactly like `runner_state.lua`. Render functions are covered by a **fake window**
that records draw calls, so layout and hover logic are assertable without a client:

```lua
local fake = FakeWindow.new()        -- records every render_* call and its bounds
panel.render(fake, model)
assert(fake:drew_text("No campaign open"))
```

That harness is part of U1, not an afterthought — without it every later panel is untestable and
the split in §2.1 quietly stops being enforced.

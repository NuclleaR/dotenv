// Popup with one switch per tab-bar button of mine (Herdr's Files and Changes are
// left to Herdr). "This space" sets them for the shown space only; "Default" for
// every space that did not choose otherwise. Opened by the sliders button in the
// tab bar, or by `mod.open:my-panels` from keys.json. Applies at once, persisted.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { setShared, shared, spaces, theme } from "herdr";
import { SWITCHES, isOn, overridden, resetSpace, setSwitch } from "./switches.js";

const KEY = "my.panels";

export default class MyPanels extends View {
  init() {
    this.scope = "space";
  }

  render() {
    const t = theme();
    const store = shared(KEY);
    const space = spaces().find((s) => s.active) ?? null;
    const inSpace = Boolean(space) && this.scope === "space";
    const scope = inSpace ? space.id : "default";
    const own = inSpace && SWITCHES.some((s) => overridden(store, scope, s.id));

    const tab = (id, label) => div().id(`scope-${id}`).flex_1().h(24).flex().items_center().justify_center()
      .rounded(5).cursor_pointer().text_size(12)
      .bg((inSpace ? "space" : "default") === id ? t.selected : t.popover)
      .text_color((inSpace ? "space" : "default") === id ? t.foreground : t.muted)
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => { this.scope = id; cx.notify(); })
      .child(label);
    const toggle = (on) => h_flex().flex_none().w(28).h(16).p(2).rounded(8).items_center()
      .bg(on ? t.accent : t.border).when(on, (e) => e.justify_end())
      .child(div().size(12).rounded(6).bg(on ? t.accent_foreground : t.background));

    return v_flex().size_full().p(6).gap(2).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().gap(2).p(2).rounded(6).border_1().border_color(t.border)
        .when(Boolean(space), (e) => e.child(tab("space", "This space")))
        .child(tab("default", "Default")))
      .child(div().px(8).pt(6).pb(4).truncate().text_size(11).text_color(t.muted)
        .child(inSpace ? `Space "${space.name}"` : "Spaces that did not choose"))
      .children(SWITCHES.map((s) => {
        const on = isOn(store, inSpace ? scope : null, s.id);
        return h_flex().id(`switch-${s.id}`).h(30).px(8).gap(8).items_center().rounded(6).cursor_pointer()
          .hover((st) => st.bg(t.hover))
          .on_click(() => setShared(KEY, setSwitch(store, scope, s.id, !on)))
          .child(div().flex_1().child(s.label))
          // A dot: this space chose it, the default does not apply.
          .when(inSpace && overridden(store, scope, s.id), (e) => e.child(div().flex_none().size(6).rounded(3).bg(t.accent)))
          .child(toggle(on));
      }))
      .when(own, (e) => e.child(div().id("reset-space").mt(4).px(8).py(4).rounded(6).cursor_pointer()
        .text_size(12).text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => setShared(KEY, resetSpace(store, scope)))
        .child("Reset this space to default")));
  }
}

import QtQuick
import QtTest

import ".."

TestCase {
  name: "ShortcutModifiers"

  ShortcutModifiers {
    id: modifiers
  }

  function test_flagsForSequence_setsOnlyTheNamedModifiers() {
    compare(modifiers.flagsForSequence("Ctrl+F"), Qt.ControlModifier)
    compare(modifiers.flagsForSequence("Shift+Left"), Qt.ShiftModifier)
    compare(modifiers.flagsForSequence("Alt+Right"), Qt.AltModifier)
    compare(modifiers.flagsForSequence("Ctrl+Shift+A"),
      Qt.ControlModifier | Qt.ShiftModifier)
  }

  function test_flagsForSequence_isZeroWithoutModifiers() {
    compare(modifiers.flagsForSequence("Space"), 0)
    compare(modifiers.flagsForSequence(""), 0)
    compare(modifiers.flagsForSequence(null), 0)
    compare(modifiers.flagsForSequence(undefined), 0)
  }

  function test_flagsForSequence_ignoresSuperBecauseHintsDoNotUseIt() {
    compare(modifiers.flagsForSequence("Super+Shift+M"), Qt.ShiftModifier)
  }

  function test_flagFor_mapsEachHintModifierKey() {
    compare(modifiers.flagFor(Qt.Key_Control), Qt.ControlModifier)
    compare(modifiers.flagFor(Qt.Key_Shift), Qt.ShiftModifier)
    compare(modifiers.flagFor(Qt.Key_Alt), Qt.AltModifier)
    compare(modifiers.flagFor(Qt.Key_AltGr), Qt.AltModifier)
  }

  function test_flagFor_isZeroForKeysThatDoNotShowHints() {
    compare(modifiers.flagFor(Qt.Key_Meta), 0)
    compare(modifiers.flagFor(Qt.Key_A), 0)
  }

  function test_isHintModifierKey_acceptsOnlyKeysThatRevealHints() {
    verify(modifiers.isHintModifierKey(Qt.Key_Control))
    verify(modifiers.isHintModifierKey(Qt.Key_Shift))
    verify(modifiers.isHintModifierKey(Qt.Key_Alt))
    verify(modifiers.isHintModifierKey(Qt.Key_AltGr))
    verify(!modifiers.isHintModifierKey(Qt.Key_Meta))
    verify(!modifiers.isHintModifierKey(Qt.Key_A))
  }

  // Meta is a modifier for the purpose of "did the user press a real key",
  // even though holding it reveals no hints.
  function test_isModifierKey_alsoCountsMeta() {
    verify(modifiers.isModifierKey(Qt.Key_Meta))
    verify(modifiers.isModifierKey(Qt.Key_Control))
    verify(!modifiers.isModifierKey(Qt.Key_A))
  }

  function test_flagsAfterEvent_keepsHeldModifiersOnPlainKeyRelease() {
    var held = Qt.ControlModifier
    compare(modifiers.flagsAfterEvent(0, false, held, Qt.Key_A), held)
  }

  function test_flagsAfterEvent_clearsTheReleasedModifier() {
    compare(modifiers.flagsAfterEvent(Qt.ControlModifier, false,
      Qt.ControlModifier, Qt.Key_Control), 0)
  }

  function test_flagsAfterEvent_addsThePressedModifier() {
    compare(modifiers.flagsAfterEvent(0, true, 0, Qt.Key_Shift),
      Qt.ShiftModifier)
  }
}

function setupKeyboard(remoteConsole) {
  var Keyboard = window.SimpleKeyboard.default;

  var shiftMod = false;
  var ctrlMod = false;
  var altMod = false;
  var metaMod = false;
  var capslock = false;

  var commonKeyboardOptions = {
    onChange: input => onChange(input),
    onKeyPress: button => onKeyPress(button),
    theme: "simple-keyboard hg-theme-default hg-layout-default",
    physicalKeyboardHighlight: true,
    syncInstanceInputs: true,
    mergeDisplay: true,
    debug: false
  };

  var keyboard = new Keyboard(".simple-keyboard-main", {
    ...commonKeyboardOptions,
    layout: {
      default: [
        "{escape} {f1} {f2} {f3} {f4} {f5} {f6} {f7} {f8} {f9} {f10} {f11} {f12}",
        "` 1 2 3 4 5 6 7 8 9 0 - = {backspace}",
        "{tab} q w e r t y u i o p [ ] \\",
        "{capslock} a s d f g h j k l ; ' {enter}",
        "{shiftleft} z x c v b n m , . / {shiftright}",
        "{controlleft} {metaleft} {altleft} {space} {altright} {metaright}"
      ],
      shift: [
        "{escape} {f1} {f2} {f3} {f4} {f5} {f6} {f7} {f8} {f9} {f10} {f11} {f12}",
        "~ ! @ # $ % ^ & * ( ) _ + {backspace}",
        "{tab} Q W E R T Y U I O P { } |",
        '{capslock} A S D F G H J K L : " {enter}',
        "{shiftleft} Z X C V B N M < > ? {shiftright}",
        "{controlleft} {metaleft} {altleft} {space} {altright} {metaright}"
      ]
    },
    display: {
      "{escape}": "esc ⎋",
      "{tab}": "tab ⇥",
      "{backspace}": "backspace ⌫",
      "{enter}": "enter ↵",
      "{capslock}": "caps lock ⇪",
      "{shiftleft}": "shift ⇧",
      "{shiftright}": "shift ⇧",
      "{controlleft}": "ctrl ⌃",
      "{controlright}": "ctrl ⌃",
      "{altleft}": "alt ⌥",
      "{altright}": "alt ⌥",
      "{metaleft}": "cmd ⌘",
      "{metaright}": "cmd ⌘"
    }
  });

  var keyboardControlPad = new Keyboard(".simple-keyboard-control", {
    ...commonKeyboardOptions,
    layout: {
      default: [
        "{prtscr} {scrolllock} {pause}",
        "{insert} {home} {pageup}",
        "{delete} {end} {pagedown}"
      ]
    }
  });

  var keyboardArrows = new Keyboard(".simple-keyboard-arrows", {
    ...commonKeyboardOptions,
    layout: {
      default: ["{arrowup}", "{arrowleft} {arrowdown} {arrowright}"]
    }
  });

  function onChange(input) {
    keyboard.setInput('');
  }

  function onKeyPress(button) {
    if (
      button === "{shift}" ||
      button === "{shiftleft}" ||
      button === "{shiftright}" ||
      button === "{capslock}"
    )
      handleShift();

    switch (button) {
      case '{altleft}':
      case '{altright}':
        altMod = !altMod;
        return;

      case '{controlleft}':
      case '{controlright}':
        ctrlMod = !ctrlMod;
        return;

      case '{metaleft}':
      case '{metaright}':
        metaMod = !metaMod;
        return;

      case '{shift}':
      case '{shiftleft}':
      case '{shiftright}':
        shiftMod = !shiftMod;
        return;

      case '{capslock}':
        capslock = !capslock;
        shiftMod = capslock;
        return;
    }

    var key, keyCode;
    var code = "";
    var modifiers = {
      ctrlKey: ctrlMod,
      shiftKey: shiftMod,
      altKey: altMod,
      metaKey: metaMod
    };

    switch (button) {
      case '{backspace}':
        key = "Backspace";
        keyCode = 8;
        break;
      case '{tab}':
        key = 'Tab';
        keyCode = 9;
        break;
      case '{enter}':
        key = 'Enter';
        keyCode = 13;
        break;
      case '{escape}':
        key = 'Escape';
        keyCode = 27;
        break;
      case '{arrowleft}':
        key = 'ArrowLeft';
        keyCode = 37;
        break;
      case '{arrowright}':
        key = 'ArrowRight';
        keyCode = 39;
        break;
      case '{arrowup}':
        key = 'ArrowUp';
        keyCode = 38;
        break;
      case '{arrowdown}':
        key = 'ArrowDown';
        keyCode = 40;
        break;
      case '{insert}':
        key = 'Insert';
        keyCode = 45;
        break;
      case '{delete}':
        key = 'Delete';
        keyCode = 46;
        break;
      case '{home}':
        key = 'Home';
        keyCode = 36;
        break;
      case '{end}':
        key = 'End';
        keyCode = 35;
        break;
      case '{pageup}':
        key = 'PageUp';
        keyCode = 33;
        break;
      case '{pagedown}':
        key = 'PageDown';
        keyCode = 34;
        break;
      case '{f1}':
        key = 'F1';
        keyCode = 112;
        break;
      case '{f2}':
        key = 'F2';
        keyCode = 113;
        break;
      case '{f3}':
        key = 'F3';
        keyCode = 114;
        break;
      case '{f4}':
        key = 'F4';
        keyCode = 115;
        break;
      case '{f5}':
        key = 'F5';
        keyCode = 116;
        break;
      case '{f6}':
        key = 'F6';
        keyCode = 117;
        break;
      case '{f7}':
        key = 'F7';
        keyCode = 118;
        break;
      case '{f8}':
        key = 'F8';
        keyCode = 119;
        break;
      case '{f9}':
        key = 'F9';
        keyCode = 120;
        break;
      case '{f10}':
        key = 'F10';
        keyCode = 121;
        break;
      case '{f11}':
        key = 'F11';
        keyCode = 122;
        break;
      case '{f12}':
        key = 'F12';
        keyCode = 123;
        break;
      case '{space}':
        key = ' ';
        code = 'Space';
        keyCode = 32;
        resetModifiers();
        break;
      case '!':
      case '"':
      case '#':
      case '$':
      case '%':
      case '^':
      case '&':
      case '*':
      case '(':
      case ')':
      case '_':
      case '+':
        key = button;
        keyCode = key.charCodeAt(0) + 15;
        resetModifiers();
        break;
      case '-':
        key = button;
        keyCode = 189;
        resetModifiers();
        break;
      case '{':
        key = button;
        keyCode = 219;
        resetModifiers();
        break;
      case '}':
        key = button;
        keyCode = 221;
        resetModifiers();
        break;
      default:
        if (button.length != 1)
          return;

        key = button;
        keyCode = key.charCodeAt(0);
        resetModifiers();
    }

    remoteConsole.sendKey(key, code, keyCode, modifiers);
  }

  function resetModifiers() {
    if (shiftMod && !capslock) {
      shiftMod = false;
      handleShift();
    }

    altMod = false;
    ctrlMod = false;
    metaMod = false;
  }

  function handleShift() {
    var currentLayout = keyboard.options.layoutName;
    var shiftToggle = currentLayout === "default" ? "shift" : "default";

    keyboard.setOptions({
      layoutName: shiftToggle
    });
  }
}

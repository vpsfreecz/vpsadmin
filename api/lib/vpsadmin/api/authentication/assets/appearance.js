(function () {
  'use strict';
  var storageKey = 'vpsadmin.oauth.appearance.v1';
  var incoming = INITIAL_PREFERENCE;
  function valid(value) { return ['light', 'dark', 'auto'].indexOf(value) !== -1; }
  var saved;
  try { saved = localStorage.getItem(storageKey); } catch (_) {}
  var preference = valid(incoming) ? incoming : (valid(saved) ? saved : 'auto');
  document.documentElement.dataset.appearance = preference;

  function themedUrl(value) {
    var url = new URL(value, location.href);
    if (url.origin === location.origin) url.searchParams.set('theme', preference);
    return url.href;
  }
  function apply() {
    document.documentElement.dataset.appearance = preference;
    document.querySelectorAll('[data-appearance-field]').forEach(function (field) {
      field.value = preference;
    });
    document.querySelectorAll('[data-appearance-link]').forEach(function (link) {
      link.href = themedUrl(link.href);
    });
    document.querySelectorAll('.appearance-controls input').forEach(function (input) {
      input.checked = input.value === preference;
    });
  }
  window.vpsadminAppearance = { url: themedUrl };
  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.appearance-controls').forEach(function (controls) {
      controls.addEventListener('change', function (event) {
        if (!valid(event.target.value)) return;
        preference = event.target.value;
        try { localStorage.setItem(storageKey, preference); } catch (_) {}
        apply();
      });
      controls.hidden = false;
    });
    apply();
  });
}());

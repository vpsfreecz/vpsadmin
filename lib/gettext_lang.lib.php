<?php
class Lang {
  private $current_lang;
  private $xtpl;
  private $langs;
  const c_name = 'vpsAdmin-l_code';

  function __construct ($langs, &$xtpl) {
    $this->langs = $langs;
    $this->xtpl  = $xtpl;

    if (isset($_COOKIE[self::c_name]) && isset($this->langs[$_COOKIE[self::c_name]])) {
      $lang = $_COOKIE[self::c_name];
    } else {
      $lang = "en_US.utf8";
    }
    $this->set_current_lang($lang);
  }

  public function lang_switcher() {
    foreach ($this->langs as $lang) {
      if ($lang["code"] == $this->current_lang)
        $class = "chosen";
      else
        $class = "";

      $this->xtpl->lang_add($lang["code"], $lang["icon"], $lang["lang"], $class);
    }
  }
  // $newlang = $lang['code']
  public function change($newlang) {
    if (isset($this->langs[$newlang])) {
      $this->set_current_lang($newlang);
      Header("Location: ". $this->xtpl->get_prev_url());

      return true;
    } else {
      echo _("ERROR: Language not found");

      return false;
    }
  }

  private function set_current_lang($newlang) {
    $this->current_lang = $newlang;

    @putenv("LC_ALL=".$newlang); // for WinXP SP3
    T_setlocale(LC_ALL, $newlang);
    T_bindtextdomain("vpsAdmin", WWW_ROOT."/lang/locale/");
    T_bind_textdomain_codeset("vpsAdmin", "UTF-8");
    T_textdomain("vpsAdmin");

    setcookie(self::c_name, $this->current_lang, time()+86400*7);
  }

  public function get_current_lang() {
    return $this->current_lang;
  }
}
?>

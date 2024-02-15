<?php
/*
    ./lib/xtemplate.lib.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>

    Xtemplate
     Copyright (c) 2000-2001 Barnabas Debreceni [cranx@users.sourceforge.net] XTemplate
     Copyright (c) 2002-2007 Jeremy Coates [cocomp@users.sourceforge.net] XTemplate & CachingXTemplate

*/
// if we are using xtemplate, this is not CLI application
$_SESSION["cli_mode"] = false;

class XTemplate
{
    public $filecontents = '';
    public $blocks = [];
    public $parsed_blocks = [];
    public $preparsed_blocks = [];
    public $block_parse_order = [];
    public $sub_blocks = [];
    public $vars = [];
    public $filevars = [];
    public $filevar_parent = [];
    public $filecache = [];
    public $tpldir = '';
    public $files = null;
    public $filename = '';
    public $file_delim = '';//"/\{FILE\s*\"([^\"]+)\"\s*\}/m";
    public $filevar_delim = '';//"/\{FILE\s*\{([A-Za-z0-9\._]+?)\}\s*\}/m";
    public $filevar_delim_nl = '';//"/^\s*\{FILE\s*\{([A-Za-z0-9\._]+?)\}\s*\}\s*\n/m";
    public $block_start_delim = '<!-- ';         /* block start delimiter */
    public $block_end_delim = '-->';                 /* block end delimiter */
    public $block_start_word = 'BEGIN:';         /* block start word */
    public $block_end_word = 'END:';                 /* block end word */

    public $tag_start_delim = '{';
    public $tag_end_delim = '}';

    public $mainblock = 'main';
    public $output_type = 'HTML';
    public $_null_string = ['' => ''];             /* null string for unassigned vars */
    public $_null_block = ['' => ''];  /* null string for unassigned blocks */
    public $_error = '';
    public $_autoreset = true;                                     /* auto-reset sub blocks */
    public $_ignore_missing_blocks = true ;          // NW 17 oct 2002 - Set to FALSE to
    public $_file_name_full_path = '';
    public $table_rows = 0;
    public function __construct($file, $tpldir = '', $files = null, $mainblock = 'main', $autosetup = true)
    {
        $this->filename = $file;
        $this->_file_name_full_path = realpath($file);
        $this->tpldir = $tpldir;
        if (is_array($files)) {
            $this->files = $files;
        }
        $this->mainblock = $mainblock;
        if ($autosetup) {
            $this->setup();
        }
    }
    public function restart($file, $tpldir = '', $files = null, $mainblock = 'main', $autosetup = true, $tag_start = '{', $tag_end = '}')
    {
        $this->filename = $file;
        $this->_file_name_full_path = realpath($file);
        $this->tpldir = $tpldir;
        if (is_array($files)) {
            $this->files = $files;
        }
        $this->mainblock = $mainblock;
        $this->tag_start_delim = $tag_start;
        $this->tag_end_delim = $tag_end;
        $this->filecontents = '';
        $this->blocks = [];
        $this->parsed_blocks = [];
        $this->preparsed_blocks = [];
        $this->block_parse_order = [];
        $this->sub_blocks = [];
        $this->vars = [];
        $this->filevars = [];
        $this->filevar_parent = [];
        $this->filecache = [];
        if ($autosetup) {
            $this->setup();
        }
    }
    public function setup($add_outer = false)
    {
        $this->tag_start_delim = preg_quote($this->tag_start_delim);
        $this->tag_end_delim = preg_quote($this->tag_end_delim);
        $this->file_delim = "/" . $this->tag_start_delim . "FILE\s*\"([^\"]+)\"\s*" . $this->tag_end_delim . "/m";
        $this->filevar_delim = "/" . $this->tag_start_delim . "FILE\s*" . $this->tag_start_delim . "([A-Za-z0-9\._]+?)" . $this->tag_end_delim . "\s*" . $this->tag_end_delim . "/m";
        $this->filevar_delim_nl = "/^\s*" . $this->tag_start_delim . "FILE\s*" . $this->tag_start_delim . "([A-Za-z0-9\._]+?)" . $this->tag_end_delim . "\s*" . $this->tag_end_delim . "\s*\n/m";
        if (empty($this->filecontents)) {
            $this->filecontents = $this->_r_getfile($this->filename);
        }
        if ($add_outer) {
            $this->_add_outer_block();
        }
        $this->blocks = $this->_maketree($this->filecontents, '');
        $this->filevar_parent = $this->_store_filevar_parents($this->blocks);
    }
    public function assign($name, $val = '')
    {
        if (is_array($name)) {
            foreach ($name as $k => $v) {
                $this->vars[$k] = $v;
            }
        } else {
            $this->vars[$name] = $val;
        }
    }

    public function assign_file($name, $val = '')
    {
        if (is_array($name)) {
            foreach ($name as $k => $v) {
                $this->_assign_file_sub($k, $v);
            }
        } else {
            $this->_assign_file_sub($name, $val);
        }
    }

    public function parse($bname)
    {
        if (isset($this->preparsed_blocks[$bname])) {
            $copy = $this->preparsed_blocks[$bname];
        } elseif (isset($this->blocks[$bname])) {
            $copy = $this->blocks[$bname];
        } elseif ($this->_ignore_missing_blocks) {
            $this->_set_error("parse: blockname [$bname] does not exist");
            return;
        } else {
            $this->_set_error("parse: blockname [$bname] does not exist");
        }
        if (!isset($copy)) {
            die('Block: ' . $bname);
        }
        $copy = preg_replace($this->filevar_delim_nl, '', $copy);
        $var_array = [];
        preg_match_all("/" . $this->tag_start_delim . "([A-Za-z0-9\._]+? ?#?.*?)" . $this->tag_end_delim . "/", $copy, $var_array);
        $var_array = $var_array[1];
        foreach ($var_array as $k => $v) {
            $any_comments = explode('#', $v);
            $v = rtrim($any_comments[0]);
            if (sizeof($any_comments) > 1) {
                $comments = $any_comments[1];
            } else {
                $comments = '';
            }
            $sub = explode('.', $v);
            if ($sub[0] == '_BLOCK_') {
                unset($sub[0]);
                $bname2 = implode('.', $sub);
                $var = $this->parsed_blocks[$bname2] ?? null;
                $nul = (!isset($this->_null_block[$bname2])) ? $this->_null_block[''] : $this->_null_block[$bname2];
                if ($var == '') {
                    if ($nul == '') {
                        $copy = preg_replace("/" . $this->tag_start_delim . $v . $this->tag_end_delim . "/m", '', $copy);
                    } else {
                        $copy = preg_replace("/" . $this->tag_start_delim . $v . $this->tag_end_delim . "/", "$nul", $copy);
                    }
                } else {
                    $var = trim($var);
                    $var = str_replace('\\', '\\\\', $var);
                    $var = str_replace('$', '\\$', $var);
                    $var = str_replace('\\|', '|', $var);
                    $copy = preg_replace("|" . $this->tag_start_delim . $v . $this->tag_end_delim . "|", "$var", $copy);
                }
            } else {
                $var = $this->vars;
                foreach ($sub as $v1) {
                    if (!isset($var[$v1]) || (!is_array($var[$v1]) && strlen($var[$v1]) == 0)) {
                        if (defined($v1)) {
                            $var[$v1] = constant($v1);
                        } else {
                            $var[$v1] = null;
                        }
                    }
                    $var = $var[$v1];
                }
                $nul = (!isset($this->_null_string[$v])) ? ($this->_null_string[""]) : ($this->_null_string[$v]);
                $var = (!isset($var)) ? $nul : $var;
                if ($var == '') {
                    $copy = preg_replace("|\s*" . $this->tag_start_delim . $v . " ?#?" . $comments . $this->tag_end_delim . "\s*\n|m", '', $copy);
                }
                $var = trim($var);
                $var = str_replace('\\', '\\\\', $var);
                $var = str_replace('$', '\\$', $var);
                $var = str_replace('\\|', '|', $var);
                $copy = preg_replace("|" . $this->tag_start_delim . $v . " ?#?" . $comments . $this->tag_end_delim . "|", "$var", $copy);
            }
        }
        if (isset($this->parsed_blocks[$bname])) {
            $this->parsed_blocks[$bname] .= $copy;
        } else {
            $this->parsed_blocks[$bname] = $copy;
        }
        /* reset sub-blocks */
        if ($this->_autoreset && (!empty($this->sub_blocks[$bname]))) {
            reset($this->sub_blocks[$bname]);
            foreach ($this->sub_blocks[$bname] as $k => $v) {
                $this->reset($v);
            }
        }
    }
    public function rparse($bname)
    {
        if (!empty($this->sub_blocks[$bname])) {
            reset($this->sub_blocks[$bname]);
            foreach ($this->sub_blocks[$bname] as $k => $v) {
                if (!empty($v)) {
                    $this->rparse($v);
                }
            }
        }
        $this->parse($bname);
    }
    public function insert_loop($bname, $var, $value = '')
    {
        $this->assign($var, $value);
        $this->parse($bname);
    }
    public function array_loop($bname, $var, &$values)
    {
        if (is_array($values)) {
            foreach($values as $v) {
                $this->assign($var, $v);
                $this->parse($bname);
            }
        }
    }
    public function text($bname = '')
    {
        $text = '';
        $bname = !empty($bname) ? $bname : $this->mainblock;
        $text .= $this->parsed_blocks[$bname] ?? $this->get_error();
        return $text;
    }
    public function out($bname)
    {
        $out = $this->text($bname);
        echo $out;
    }
    public function out_file($bname, $fname)
    {
        if (!empty($bname) && !empty($fname) && is_writeable($fname)) {
            $fp = fopen($fname, 'w');
            fwrite($fp, $this->text($bname));
            fclose($fp);
        }
    }
    public function reset($bname)
    {
        $this->parsed_blocks[$bname] = '';
    }
    public function parsed($bname)
    {
        return (!empty($this->parsed_blocks[$bname]));
    }
    public function SetNullString($str, $varname = '')
    {
        $this->_null_string[$varname] = $str;
    }
    public function SetNullBlock($str, $bname = '')
    {
        $this->_null_block[$bname] = $str;
    }
    public function set_autoreset()
    {
        $this->_autoreset = true;
    }
    public function clear_autoreset()
    {
        $this->_autoreset = false;
    }
    public function get_error()
    {
        $retval = false;
        if ($this->_error != '') {
            switch ($this->output_type) {
                case 'HTML':
                case 'html':
                    $retval = '<b>[XTemplate]</b><ul>' . nl2br(str_replace('* ', '<li>', str_replace(" *\n", "</li>\n", $this->_error))) . '</ul>';
                    break;
                default:
                    $retval = '[XTemplate] ' . str_replace(' *\n', "\n", $this->_error);
                    break;
            }
        }
        return $retval;
    }
    public function _maketree($con, $parentblock = '')
    {
        $blocks = [];
        $con2 = explode($this->block_start_delim, $con);
        if (!empty($parentblock)) {
            $block_names = explode('.', $parentblock);
            $level = sizeof($block_names);
        } else {
            $block_names = [];
            $level = 0;
        }
        foreach($con2 as $k => $v) {
            $patt = "($this->block_start_word|$this->block_end_word)\s*(\w+) ?#?.*?\s*$this->block_end_delim(.*)";
            $res = [];
            if (preg_match_all("/$patt/ims", $v, $res, PREG_SET_ORDER)) {
                $block_word	= $res[0][1];
                $block_name	= $res[0][2];
                $content	= $res[0][3];
                if (strtoupper($block_word) == $this->block_start_word) {
                    $parent_name = implode('.', $block_names);
                    $block_names[++$level] = $block_name;
                    $cur_block_name = implode('.', $block_names);
                    $this->block_parse_order[] = $cur_block_name;
                    $blocks[$cur_block_name] = isset($blocks[$cur_block_name]) ? $blocks[$cur_block_name] . $content : $content;
                    $blocks[$parent_name] .= str_replace('\\', '', $this->tag_start_delim) . '_BLOCK_.' . $cur_block_name . str_replace('\\', '', $this->tag_end_delim);
                    $this->sub_blocks[$parent_name][] = $cur_block_name;
                    $this->sub_blocks[$cur_block_name][] = '';
                } elseif (strtoupper($block_word) == $this->block_end_word) {
                    unset($block_names[$level--]);
                    $parent_name = implode('.', $block_names);
                    $blocks[$parent_name] .= $res[0][3];
                }
            } else {
                $tmp = implode('.', $block_names);
                if ($k) {
                    $blocks[$tmp] .= $this->block_start_delim;
                }
                $blocks[$tmp] = isset($blocks[$tmp]) ? $blocks[$tmp] . $v : $v;
            }
        }
        return $blocks;
    }
    public function _assign_file_sub($name, $val)
    {
        if (isset($this->filevar_parent[$name])) {
            if ($val != '') {
                $val = $this->_r_getfile($val);
                foreach($this->filevar_parent[$name] as $parent) {
                    if (isset($this->preparsed_blocks[$parent]) && !isset($this->filevars[$name])) {
                        $copy = $this->preparsed_blocks[$parent];
                    } elseif (isset($this->blocks[$parent])) {
                        $copy = $this->blocks[$parent];
                    }
                    $res = [];
                    preg_match_all($this->filevar_delim, $copy, $res, PREG_SET_ORDER);
                    if (is_array($res) && isset($res[0])) {
                        foreach ($res[0] as $v) {
                            $copy = preg_replace("/" . preg_quote($v) . "/", "$val", $copy);
                            $this->preparsed_blocks = array_merge($this->preparsed_blocks, $this->_maketree($copy, $parent));
                            $this->filevar_parent = array_merge($this->filevar_parent, $this->_store_filevar_parents($this->preparsed_blocks));
                        }
                    }
                }
            }
        }
        $this->filevars[$name] = $val;
    }
    public function _store_filevar_parents($blocks)
    {
        $parents = [];
        foreach ($blocks as $bname => $con) {
            $res = [];
            preg_match_all($this->filevar_delim, $con, $res);
            foreach ($res[1] as $k => $v) {
                $parents[$v][] = $bname;
            }
        }
        return $parents;
    }
    public function _set_error($str)
    {
        $this->_error .= '* ' . $str . " *\n";
    }
    public function _getfile($file)
    {
        if (!isset($file)) {
            $this->_set_error('!isset file name!' . $file);
            return '';
        }
        if (isset($this->files)) {
            if (isset($this->files[$file])) {
                $file = $this->files[$file];
            }
        }
        if (!empty($this->tpldir)) {
            $file = $this->tpldir . '/' . $file;
        }
        if (isset($this->filecache[$file])) {
            $file_text = $this->filecache[$file];
        } else {
            if (is_file($file)) {
                if (!($fh = fopen($file, 'r'))) {
                    $this->_set_error('Cannot open file: ' . $file);
                    return '';
                }
                $file_text = fread($fh, filesize($file));
                fclose($fh);
            } else {
                $this->_set_error("[" . realpath($file) . "] ($file) does not exist");
                $file_text = "<b>__XTemplate fatal error: file [$file] does not exist__</b>";
            }
            $this->filecache[$file] = $file_text;
        }
        return $file_text;
    }
    public function _r_getfile($file)
    {
        $text = $this->_getfile($file);
        $res = [];
        while (preg_match($this->file_delim, $text, $res)) {
            $text2 = $this->_getfile($res[1]);
            $text = preg_replace("'" . preg_quote($res[0]) . "'", $text2, $text);
        }
        return $text;
    }
    public function _add_outer_block()
    {
        $before = $this->block_start_delim . $this->block_start_word . ' ' . $this->mainblock . ' ' . $this->block_end_delim;
        $after = $this->block_start_delim . $this->block_end_word . ' ' . $this->mainblock . ' ' . $this->block_end_delim;
        $this->filecontents = $before . "\n" . $this->filecontents . "\n" . $after;
    }
    public function _pre_var_dump()
    {
        echo '<pre>';
        var_dump(func_get_args());
        echo '</pre>';
    }
    /* XTemplate extensions for vpsAdmin for lazy programmers */
    /**
      * Set title of the page
      * @param $title - title of page
    */
    public function title($title)
    {
        $this->assign('TITLE', $title);
    }
    public function title2($title2)
    {
        $this->assign('S_TITLE', $title2);
        $this->parse('main.s_title');
    }
    public function title3($title3)
    {
        $this->assign('S_S_TITLE', $title3);
        $this->parse('main.s_s_title');
    }
    /**
      * @param $code - lang code
      * @param $icon - lang icon code
      * @param $lang - language name
      * @param $class - class of image
    **/
    public function lang_add($code, $icon, $lang, $class)
    {
        $this->assign('LANG_CODE', $code);
        $this->assign('LANG_ICON', $icon);
        $this->assign('LANG_IMG_CLASS', $class);
        $this->assign('LANG_LANG', $lang);
        $this->assign('PREV_URL', base64_encode(curPageURL()));
        $this->parse('main.langitem');
    }
    /**
      * Parse out the login box
      * @param $logged - is user logged in?
      * @param $user_name - if so, what is is nick?
      */
    public function logbox($logged = false, $user_name = 'none', $is_admin = false, $maint_mode = false)
    {
        if ($logged) {
            if ($is_admin) {
                $this->assign("L_SEARCH", _("Search"));
                $this->assign("V_SEARCH", $_SESSION["jumpto"] ?? '');
                $this->assign("L_JUMP", _("Jump"));
                $this->parse("main.loggedbox.jumpto");

                if ($maint_mode) {
                    $this->assign("V_CSRF_TOKEN", csrf_token());
                    $this->assign("L_MAINTENANCE_MODE_ON", _("Maintenance mode status: ON"));
                    $this->parse("main.loggedbox.is_admin.maintenance_mode_on");
                } else {
                    $this->assign("L_MAINTENANCE_MODE_OFF", _("Maintenance mode status: OFF"));
                    $this->parse("main.loggedbox.is_admin.maintenance_mode_off");
                }
                $this->assign("L_DROP_PRIVILEGES", _("Drop privileges"));
                $this->assign("V_NEXT", urlencode($_SERVER["REQUEST_URI"]));
                $this->parse("main.loggedbox.is_admin");
            } else {
                $this->assign('L_USER_ID', $_SESSION["user"]["id"]);
                $this->assign('L_EDIT_PROFILE', _("Edit profile"));
                $this->parse("main.loggedbox.not_admin");

                $contextSwitch = $_SESSION["context_switch"] ?? null;
                if ($contextSwitch) {
                    $this->assign('L_REGAIN_PRIVILEGES', _("Regain privileges"));
                    $this->assign('V_NEXT', urlencode($_SERVER["REQUEST_URI"]));
                    $this->parse('main.loggedbox.context_switch');
                }
            }
            $this->assign('USER_NAME', $user_name);
            $this->parse('main.loggedbox');
        } else {
            $this->parse('main.logbox');
        }
    }
    /**
      * Add item to menu
      * @param $title - title of the perex
      * @param $link - URL link of item
      * @param $active - Is user currently here?
      * @param $is_last - Is this item last in the menu?
      */
    public function menu_add($title = 'Titulek', $link = '#', $active = false, $is_last = false)
    {
        $this->assign('MENU_LINK', $link);
        $this->assign('MENU_TITLE', $title);
        $this->assign('MENU_ACTIVE', ($active) ? 'id="nav-active"' : '');
        $this->assign('MENU_LAST', ($is_last) ? 'class="last"' : '');
        $this->parse('main.menu_item');
    }
    /**
      * Add perex to page
      * @param $title - title of the perex
      * @param $content - HTML content of the perex
      */
    public function perex($title, $content)
    {
        $this->assign('PEREX_TITLE', $title);
        $this->assign('PEREX_CONTENT', $content);
        $this->parse('main.perex');
    }
    /**
      * Add perex - command output to page
      * @param $title - title
      * @param $output - array of lines
      */
    public function perex_cmd_output($title, $output)
    {
        $this->assign('PEREX_TITLE', $title);
        if (is_array($output)) {
            foreach ($output as $line) {
                $content .= $line . ' <br />';
            }
        }
        $this->assign('PEREX_CONTENT', $content);
        $this->parse('main.perex');
    }
    /**
      * Format errors to a perex.
      * @param string $title
      * @param \HaveAPI\Client\Response $response
      */
    public function perex_format_errors($title, $response)
    {
        $this->perex($title, format_errors($response));
    }
    /**
      * Add link to sidebar
      * @param $title - link title
      * @param $link - link URL
      */
    public function sbar_add($title, $link)
    {
        $this->assign('SBI_TITLE', $title);
        $this->assign('SBI_LINK', $link);
        $this->parse('main.sidebar.sb_item');
    }
    public function sbar_add_fragment($html)
    {
        $this->assign('SB_FRAGMENT', $html);
        $this->parse('main.sidebar_fragment');
    }
    /**
      * Parse out the sidebar
      * @param $title - tile for the sidebar
      */
    public function sbar_out($title)
    {
        $this->assign('SB_TITLE', $title);
        $this->parse('main.sidebar');
    }
    public function table_title($title = "")
    {
        $this->assign('T_TITLE', $title);
        $this->parse('main.table.t_title');
    }
    /**
      * Add table category to table header
      * @param $name - HTML content of the category header
      */
    public function table_add_category($name)
    {
        $this->assign('TABLE_CATEGORY', $name);
        $this->parse('main.table.category');
    }
    /**
      * Add table cell
      * @param $content - HTML content of the cell
      * @param $td_back_color - HTML background color
      * @param $toright - Right side text align
      */
    public function table_td($content, $td_back_color = false, $toright = false, $colspan = '1', $rowspan = '1', $valign = null)
    {
        $tdstyle = 'style="';
        if ($td_back_color) {
            $tdstyle .= 'background:' . $td_back_color . ';';
        }
        if ($toright) {
            $tdstyle .= 'text-align:right;';
        }
        if ($valign) {
            $tdstyle .= "vertical-align: $valign;";
        }
        $tdstyle .= '" colspan="' . $colspan . '" rowspan="' . $rowspan . '"';
        $this->assign('TDSTYLE', $tdstyle);
        $this->assign('TABLE_TD', $content);
        $this->parse('main.table.tr.td');
        $this->assign('TDSTYLE', '');
    }
    /**
      * Parse out the table row
      * @param $tr_back_color - background color of
      * @param $tr_class - CSS class of row
      * @param $tr_class_hover - CSS class when mouse over
      */
    public function table_tr($tr_back_color = false, $tr_class = false, $tr_class_hover = false, $id = null)
    {
        // UPDATED BY toms
        $this->table_rows++;
        if ($tr_back_color) {
            $this->assign('TRSTYLE', 'style="background:' . $tr_back_color . '"');
        } elseif ($tr_class) {
            $this->assign('TRSTYLE', 'class="' . $tr_class . '"');
        } else {
            $this->assign('TRSTYLE', '');
        }

        if ($tr_class) {
            $this->assign('TRCLASS', $tr_class);
        } else {
            $this->assign('TRCLASS', 'none');
        }

        if ($tr_class_hover) {
            $this->assign('TRCLASS_HOVER', $tr_class_hover);
        } else {
            $this->assign('TRCLASS_HOVER', 'bg');
        }
        if ((!$tr_back_color) && (!$tr_class) && (!$tr_class_hover)) {
            if (($this->table_rows & 1) == 0) {
                $this->assign('TRSTYLE', 'class="oddrow"');
                $this->assign('TRCLASS_HOVER', 'bg');
                $this->assign('TRCLASS', 'oddrow');
            }
        }

        if ($id) {
            $this->assign('TRID', 'id="' . $id . '"');
        } else {
            $this->assign('TRID', '');
        }

        $this->parse('main.table.tr');
    }
    /**
      * Parse out the table
      */
    public function table_out($id = null)
    {
        if ($id) {
            $this->assign('TABLE_ID', 'id="' . $id . '"');
            $this->parse('main.table.table_id');
        }

        $this->table_rows = 0;
        $this->parse('main.table');
    }
    /**
      * Add form to the page, begin with this
      * @param $action - action URL
      * @param $method - GET or POST
      * @param $name - form name
      */
    public function form_create($action = '?page=', $method = 'post', $name = 'generic_form', $csrf = true)
    {
        $this->assign('TABLE_FORM_BEGIN', '<form action="' . $action . '" method="' . $method . '" name="' . $name . '" AUTOCOMPLETE=OFF>');

        $this->form_csrf('common', $csrf);
    }
    /**
     * Add a set of hidden fields
     * @param $keyvals array of field names and values
     */
    public function form_set_hidden_fields($keyvals)
    {
        $str = '';

        foreach ($keyvals as $k => $v) {
            $str .= '<input type="hidden" name="' . $k . '" value="' . h($v) . '">';
        }

        $this->assign('FORM_HIDDEN_FIELDS', $str);
    }
    /**
      * Add input to form
      * @param $label - label of textarea
      * @param $type - type of HTML input
      * @param $size - size of element
      * @param $name - $_RESULT[name]
      * @param $value - default value
      * @param $hint - helping hint
      * @param $nchar - how many characters are remaining or needed
      * @param $extra - any extra code - onmouseclick etc.
      *
      * @return uid;
      */
    public function form_add_input($label = 'popisek', $type = 'text', $size = '30', $name = 'input_fromgen', $value = '', $hint = '', $nchar = 0, $extra = '')
    {
        $uid = uniqid();

        $this->table_td($label);

        $maxlength = '';

        if ($nchar != 0) {
            $code  = moo_inputremaining("input" . $uid, "inputh" . $uid, $nchar, $uid); // see ajax.lib.php
            if ($nchar > 0) {
                $output = sprintf(
                    _("<span id='inputh%s'>%d</span> chars remaining"),
                    $uid,
                    $nchar - strlen($value)
                );

                $maxlength = 'maxlength="' . $nchar . '"';

            } else {
                $output = sprintf(
                    _("<span id='inputh%s'>%d</span> chars needed"),
                    $uid,
                    (int)(($nchar - strlen($value)) * (-1))
                );
            }

            $hint = $code . $output . ($hint ? "; $hint" : '');
        }

        $this->table_td(
            '<input type="' . $type . '" size="' . $size . '" name="' . $name . '" id="input' . $uid . '" value="' . $value . '" ' . $maxlength . ' ' . $extra . ' />'
        );

        if ($hint != '') {
            $this->table_td($hint);
        }

        $this->table_tr();

        return 'input' . $uid;
    }

    /**
      * Add input to form without label
      * @param $type - type of HTML input
      * @param $size - size of element
      * @param $name - $_RESULT[name]
      * @param $value - default value
      *
      * @return uid;
      */
    public function form_add_input_pure($type = 'text', $size = '30', $name = 'input_fromgen', $value = '')
    {
        $uid = uniqid();
        $this->table_td('<input type="' . $type . '" size="' . $size . '" name="' . $name . '" id="input' . $uid . '" value="' . h($value) . '" />');

        return 'input' . $uid;
    }

    public function form_add_number($label, $name, $value, $min = 0, $max = 999999, $step = 1, $unit = '', $hint = '')
    {
        $this->table_td($label);
        $this->form_add_number_pure($name, $value, $min, $max, $step, $unit);

        if ($hint) {
            $this->table_td($hint);
        }

        $this->table_tr();
    }

    public function form_add_number_pure($name, $value, $min = 0, $max = 999999, $step = 1, $unit = '')
    {
        $this->table_td('<input type="number" name="' . $name . '" value="' . h($value) . '" min="' . $min . '" ' . ($max > 0 ? 'max="' . $max . '"' : '') . ' step="' . $step . '">&nbsp;' . $unit);
    }

    /**
      * Add select (combobox) to form
      * @param $label - label of textarea
      * @param $name - $_RESULT[name]
      * @param $options - array of options, $option[option_name] = "Option Label"
      * @param $selected_value - default selected value
      * @param $hint - helping hint
      */
    public function form_add_select($label, $name, $options, $selected_value = '', $hint = '', $multiple = false, $size = '5', $colspan = '1')
    {
        $this->table_td($label);
        $code = ('<select  name="' . $name . '" id="input" ' . ($multiple ? 'multiple size="' . $size . '"' : '') . '>');
        if ($options) {
            foreach ($options as $key => $value) {
                if (($selected_value == $key && $selected_value != null) || ($multiple && is_array($selected_value) && in_array($key, $selected_value))) {
                    $code .= '<option selected="selected" value="' . $key . '" title="">' . h($value) . '</option>' . "\n";
                } else {
                    $code .= '<option value="' . $key . '" title="">' . h($value) . '</option>' . "\n";
                }
            }
        }
        $code .= ('</select>');
        $this->table_td($code, false, false, $colspan);
        if ($hint != '') {
            $this->table_td($hint);
        }
        $this->table_tr(false, false, false, $name);
    }

    /**
      * Add select (combobox) to form
      * @param $name - $_RESULT[name]
      * @param $options - array of options, $option[option_name] = "Option Label"
      * @param $selected_value - default selected value
      */
    public function form_add_select_pure($name, $options, $selected_value = '', $multiple = false, $size = '5')
    {
        $this->table_td($this->form_select_html(
            $name,
            $options,
            $selected_value,
            $multiple,
            $size
        ));
    }

    /**
      * Select html fragment (combobox)
      * @param $name - $_RESULT[name]
      * @param $options - array of options, $option[option_name] = "Option Label"
      * @param $selected_value - default selected value
      */
    public function form_select_html($name, $options, $selected_value = '', $multiple = false, $size = '5')
    {
        $code = ('<select  name="' . $name . '" id="input" ' . ($multiple ? 'multiple size="' . $size . '"' : '') . '>');
        if ($options) {
            foreach ($options as $key => $value) {
                if ($selected_value == $key || ($multiple && is_array($selected_value) && in_array($key, $selected_value))) {
                    $code .= '<option selected="selected" value="' . $key . '" title="">' . h($value) . '</option>' . "\n";
                } else {
                    $code .= '<option value="' . $key . '" title="">' . h($value) . '</option>' . "\n";
                }
            }
        }
        $code .= ('</select>');
        return $code;
    }

    public function form_add_datetime_pure($name, $value = null, $local = null, $min = null, $max = null, $step = null)
    {
        $input = '<input type="datetime' . ($local ? '-local' : '') . '" name="' . $name . '"';

        if ($value) {
            $input .= 'value="' . h($local ? tolocaltz($value, 'Y-m-dTH:i:s') : $value) . '" ';
        }

        if ($min) {
            $input .= 'min="' . $min . '" ';
        }

        if ($max) {
            $input .= 'max="' . $max . '" ';
        }

        if ($step) {
            $input .= 'step="' . $step . '" ';
        }

        $input .= '>';

        $this->table_td($input);
    }


    public function form_add_datetime($label, $name, $value = null, $local = null, $hint = null, $min = null, $max = null, $step = null)
    {
        $this->table_td($label);
        form_add_datetime_pure($name, $value, $local, $min, $max, $step);

        if ($hint) {
            $this->table_td($hint);
        }

        $this->table_tr();
    }

    /**
      * @param $label - label of textarea
      * @param $cols - number of columns
      * @param $rows - number of rows
      * @param $name - $_RESULT[name]
      * @param $value - default value
      * @param $hint - helping hint
      */
    public function form_add_textarea($label = 'popisek', $cols = 10, $rows = 4, $name = 'textarea_formgen', $value = '', $hint = '')
    {
        $this->table_td($label);
        $this->table_td('<textarea name="' . $name . '" cols="' . $cols . '" rows="' . $rows . '" id="input">' . h($value) . '</textarea>');
        if ($hint != '') {
            $this->table_td($hint);
        }
        $this->table_tr();
    }
    /**
      * Add textarea to form
      * @param $cols - number of columns
      * @param $rows - number of rows
      * @param $name - $_RESULT[name]
      * @param $value - default value
      * @param $hint - helping hint
      */
    public function form_add_textarea_pure($cols = 10, $rows = 4, $name = 'textarea_formgen', $value = '')
    {
        $this->table_td('<textarea name="' . $name . '" cols="' . $cols . '" rows="' . $rows . '" id="input">' . h($value) . '</textarea>');
    }
    /**
      * Add checkobox to form
      * @param $label - label of checkbox
      * @param $name - $_RESULT[name]
      * @param $value - value if checked
      * @param $checked - if it is checked by default
      * @param $hint - helping hint
      */
    public function form_add_checkbox($label = 'popisek', $name = 'input_fromgen', $value = '', $checked = false, $hint = '', $text = '')
    {
        $this->table_td($label);
        $this->table_td('<input type="checkbox" name="' . $name . '" id="input" value="' . h($value) . '" ' . (($checked) ? 'checked' : '') . ' /> ' . $text);
        if ($hint != '') {
            $this->table_td($hint);
        }
        $this->table_tr();
    }

    /**
      * Add checkobox to form without label
      * @param $name - $_RESULT[name]
      * @param $value - value if checked
      * @param $checked - if it is checked by default
      */
    public function form_add_checkbox_pure($name = 'input_fromgen', $value = '', $checked = false, $text = '')
    {
        $this->table_td('<input type="checkbox" name="' . $name . '" id="input" value="' . h($value) . '" ' . (($checked) ? 'checked' : '') . ' /> ' . $text);
    }

    /**
      * Add radio to form
      * @param $label - label of radio
      * @param $name - $_RESULT[name]
      * @param $value - value if checked
      * @param $checked - if it is checked by default
      * @param $text - text shown next to the radio button
      * @param $hint - helping hint
      */
    public function form_add_radio($label = 'popisek', $name = 'input_fromgen', $value = '', $checked = false, $text = '', $hint = '')
    {
        $this->table_td($label);
        $this->table_td('<input type="radio" name="' . $name . '" id="input" value="' . h($value) . '" ' . (($checked) ? 'checked' : '') . ' /> ' . $text);
        if ($hint != '') {
            $this->table_td($hint);
        }
    }

    /**
      * Add radio to form
      * @param $name - $_RESULT[name]
      * @param $value - value if checked
      * @param $checked - if it is checked by default
      * @param $text - text shown next to the radio button
      */
    public function form_add_radio_pure($name = 'input_fromgen', $value = '', $checked = false, $text = '', $enabled = true)
    {
        $this->table_td('<input type="radio" name="' . $name . '" id="input" value="' . h($value) . '" ' . (($checked) ? 'checked' : '') . ' ' . ($enabled ? '' : 'disabled') . ' /> ' . $text);
    }

    public function form_csrf($name = 'common', $present = true)
    {
        if ($present) {
            $this->assign('FORM_CSRF_TOKEN', '<input type="hidden" name="csrf_token" value="' . csrf_token($name) . '">');
        } else {
            $this->assign('FORM_CSRF_TOKEN', '');
        }
    }

    public function html_submit($value, $name = null)
    {
        return '<input type="submit" name="' . $name . '" value="' . $value . '" class="button" />';
    }

    /**
      * Parse out the form
      * @param $submit_label - label of submit button of the form
      */
    public function form_out_raw($id = null)
    {
        $this->assign('TABLE_FORM_END', '</form>');
        $this->table_out($id);
    }

    /**
      * Parse out the form
      * @param $submit_label - label of submit button of the form
      */
    public function form_out($submit_label, $id = null, $label = '', $colspan = '1')
    {
        $this->table_td($label);
        $this->table_td('<input type="submit" value=" ' . $submit_label . ' "  id="button"/>', false, false, $colspan);
        $this->table_tr(false, 'nodrag nodrop');
        $this->form_out_raw($id);
    }
    /**
      * Add transaction chain row to rightside shortlog
      * @param $chain - transaction chain from the API
      */
    public function transaction_chain($chain)
    {
        $this->assign('T_ID', $chain->id);
        $this->assign('T_CONCERNS', transaction_chain_concerns($chain));
        $this->assign('T_LABEL', $chain->label);
        $this->assign('T_CLASS', $chain->state);
        $this->assign('T_PROGRESS', round((100.0 / $chain->size) * $chain->progress) . '&nbsp;%');
        $this->assign('T_PROGRESS_VAL', $chain->progress);

        switch ($chain->state) {
            case 'staged':
            case 'queued':
                $this->assign('T_ICO', '<img src="template/icons/transact_pending.gif"> ');
                break;

            case "done":
                $this->assign('T_ICO', '<img src="template/icons/transact_ok.png"> ');
                break;

            case 'failed':
                $this->assign('T_ICO', '<img src="template/icons/transact_fail.png"> ');
                break;

                // 			case "warning":
                // 				$this->assign('T_ICO', '<img src="template/icons/warning.png"> ');
                // 				break;

            default:
                $this->assign('T_ICO', '<img src="template/icons/transact_fail.png"> ');
                break;
        }
        $this->parse('main.transaction_chains.item');
    }
    /**
      * Parse out rightside transact shortlog
      */
    public function transaction_chains_out()
    {
        $this->assign("L_TRANSACTION_LOG", _("Transaction log"));
        $this->assign("L_LAST10", _("last 10"));
        $this->assign("L_WHAT", _("Object"));
        $this->assign("L_ACTION", _("Action"));
        $this->assign("L_PROGRESS", _("%"));

        $this->parse('main.transaction_chains');
    }
    /**
      * @param $title - helpbox title
      * @param $content - helpbox content, must not have \<br\>'s
      */
    public function helpbox($title, $content)
    {
        $this->assign('HELPBOX_TITLE', $title);
        $this->assign('HELPBOX_CONTENT', nl2br($content));
        $this->parse('main.helpbox');
    }
    /**
      * @param $data - HTML code, which will be added above the table
      */
    public function table_begin($data)
    {
        $this->assign('TABLE_FORM_BEGIN', $data);
    }
    /**
      * @param $data - HTML code, which will be added below the table
      */
    public function table_end($data)
    {
        $this->assign('TABLE_FORM_END', $data);
    }
    /**
      * @param $content - HTML content of adminbox
      */
    public function adminbox($content)
    {
        $this->assign('ADMINBOX_CONTENT', $content);
        $this->parse('main.adminbox');
    }
    /**
      * @param $url - Where to redirect
      * @param $delay - Delay in msecs
      */
    public function delayed_redirect($url, $delay = 1500)
    {
        $script = '
		    <script language="JavaScript">
			function redirect () {
			    setTimeout("top.location.href = \'' . $url . '\'", ' . $delay . ');
			}
		    </script>
		';
        $this->assign('SCRIPT', $script);
        $this->assign('SCRIPT_BODY', 'onload="redirect()"');
    }

    /**
      * @return String/Boolean - previous url from current url or false if not available
      */
    public function get_prev_url()
    {
        if (isset($_GET['prev_url'])) {
            return base64_decode($_GET['prev_url']);
        }

        return false;
    }
}
/**
  * pages are indexed from 0, however they are displayed from 1, therefore there are some cases when -1 had to be added
  * @param $current integer - current page number
  * @param $pages   integer - number of all possible pages
  * @param $offset  integer - number of pages displayed left or right from current page
  * @param $display boolean - default false - returns HTML code, true - prints the code on STDO and also returns it;
  *
  * @return String - HTML code for the listing
  */
function gen_pages_listing($current, $pages, $offset, $display = false)
{
    $out = '<div class="page_listing">';

    $begin = 0;
    if ($current > $offset) {
        $begin = $current - $offset;
        $out .= '<a href="?page=transactions&amp;page_number=0">&laquo;</a> ';
    }

    $end = $pages;
    if (($pages - $current - 1) > $offset) {
        $end = $current + $offset;
    }

    for ($page = $begin; $page < $end; $page++) {
        $out .= '&nbsp;';
        if ($page == $current) {
            $out .= '<b>' . ($page + 1) . '</b>';
        } else {
            $out .= '<a href="?page=transactions&amp;page_number=' . $page . '">' . ($page + 1) . '</a>';
        }
        $out .= '&nbsp;';
    }
    if (($pages - 1 - $current) > $offset) {
        $out .= ' <a href="?page=transactions&amp;page_number=' . ($pages - 1) . '">&raquo;</a> ';
    }

    $out .= '</div>';

    if ($display) {
        echo $out;
    }

    return $out;
}

/**
  * function returns full URL
  *
  * return String - full URL
  */
function curPageURL()
{
    $pageURL = 'http';
    if (isset($_SERVER["HTTPS"]) && $_SERVER["HTTPS"] == "on") {
        $pageURL .= "s";
    }
    $pageURL .= "://";
    if ($_SERVER["SERVER_PORT"] != "80") {
        $pageURL .= $_SERVER["SERVER_NAME"] . ":" . $_SERVER["SERVER_PORT"] . $_SERVER["REQUEST_URI"];
    } else {
        $pageURL .= $_SERVER["SERVER_NAME"] . $_SERVER["REQUEST_URI"];
    }
    return $pageURL;
}

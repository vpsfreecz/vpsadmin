<?php
/*
    ./lib/db.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
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
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
/*
zeroSQL Library 0.3.2
Copyright 2009-2010 Pavel Snajdr <snajpa@snajpa.net>. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of
      conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list
      of conditions and the following disclaimer in the documentation and/or other materials
      provided with the distribution.

THIS SOFTWARE IS PROVIDED BY Pavel Snajdr ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Pavel Snajdr OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those of the
authors and should not be interpreted as representing official policies, either expressed
or implied, of Pavel Snajdr.

Chanelog:
16.04.2010
  - changed to mysqli, Tomas Srnka <tomas.srnka@gmail.com>
  - added SSL support, Tomas Srnka <tomas.srnka@gmail.com>

06.04.2010
  - transaction support for InnoDB added, Tomas Srnka <tomas.srnka@gmail.com>

API:
    $whereCond can be either array (where conditions are imploded with AND), or a single condition string
    $maxRecurse decides the depth of auto table connection
    $ordering what usually follows after ORDER BY statement, eg. "`id` DESC"
    $limit is what usually follows after LIMIT statement, eg. number "10" for only 10 records to select
    *Once functions are here for a single record selection,
    non-*Once ones can be used in while($record = $db->find(...)) {} fashion

    function __construct($dbConfig) {
    function diffBegin() {
    function diffEnd() {
    function revertDiff ($revertToDiffId) {
    function findByIdOnce ($tableName, $id, $maxRecurse = 1) {
    function findById ($tableName, $id, $ordering = NULL, $limit = NULL, $maxRecurse = 1, $dontKeepResource = false) {
    function findByColumnOnce ($tableName, $columnName, $columnValue, $maxRecurse = 1) {
    function findByColumn ($tableName, $columnName, $columnValue, $ordering = NULL, $limit = NULL, $maxRecurse = 1, $dontKeepResource = false) {
    function findOnce ($tableName, $whereConditions = NULL, $maxRecurse = 1) {
    function find ($tableName, $whereConditions = NULL, $ordering = NULL, $limit = NULL, $maxRecurse = 1, $dontKeepResource = false) {
    function extractByTableName ($item, $tableName) {
    function validate ($item, &$edited=NULL, $tableName = false, $replaceByWhenInvalid = "Invalid data", $replaceByWhenNull = "No data") {
    function _validate ($tested, $condition) {
    function getTableColumns ($tableName) {
    function getQueryArray ($query, $force = false, $dontCache = false) {
    function save(&$row, $tableName = NULL, $maxSaveRecurse = 0, $transactional = false) {
    function destroy($row, $transactional = false) {
    function destroyByCond($tableName, $whereConditions, $transactional = false) {
    function query($sql, $cache = false, $transactional = false) {
    function clearCache() {
    function fetchRow($handle) {
    function fetchArray($handle) {
    function fetchAssoc($handle) {
    function fetchObject($handle) {
    function numFields($ofWhat) {
    function affectedRows() {
    function insertId() {
    function check($string) {
    function __destruct() {

*/
class sql_db {
    private $db;
    private $cache = array();
    public $history = array();
    public $debug = true;
    private $diffMode = false;
    private $diff = array();
    private $diffCount = 0;

    function __construct($host,$user,$pass,$name, $sock = null, $use_socket = false) {
      $this->db = mysqli_init();
      if ($use_socket && $sock) {
        $this->db->real_connect("localhost", $user, $pass, $name, ini_get("mysqli.default_port"), $sock);      
      } else {
        $this->db->real_connect($host, $user, $pass, $name);
      }
	$this->host = $host;
	$this->user = $user;
	$this->pass = $pass;
	$this->name = $name;
  $this->sock = $sock;
  if ($this->db->connect_errno)
		die ('Unable to connect to the database. Error: '.$this->db->errno.' '.$this->db->error);
	
	$this->query('SET NAMES UTF8');

	return true;
    }

    function findByColumnOnce ($tableName, $columnName, $columnValue, $maxRecurse = 1) {
	return $this->findByColumn($tableName, $columnName, $columnValue, NULL, NULL, $maxRecurse, true);
    }

    function findByColumn ($tableName, $columnName, $columnValue, $ordering = NULL, $limit = NULL, $maxRecurse = 1, $dontKeepResource = false) {
	$tableName = "`{$this->check($tableName)}`";
	$columnName = "`{$this->check($columnName)}`";
	$columnValue = "{$this->check($columnValue)}";
	return $this->find($tableName, "$columnName = \"$columnValue\"", $ordering, $limit, $maxRecurse, $dontKeepResource);
    }

    function findOnce ($tableName, $whereConditions = NULL, $maxRecurse = 1) {
	return $this->find($tableName, $whereConditions, NULL, NULL, $maxRecurse, true);
    }

    function find ($tableName, $whereConditions = NULL, $ordering = NULL, $limit = NULL, $maxRecurse = 0, $dontKeepResource = false) {
	$toJoin = array();
	$cols = array();
	$conditions = array();
	$rows = array();
	$returnRows = array();
	$tableName = $this->check($tableName);

	if ($whereConditions) {
	    foreach ((array)$whereConditions as $cond) {
		$conditions[] = "($cond)";
	    }

	    $sql =  'SELECT * FROM '.$tableName.' WHERE '.implode(' AND ', $conditions);
	} else {
	    $sql =  'SELECT * FROM '.$tableName;
	}
	if ($ordering) {
	    $sql .= ' ORDER BY '.$ordering;
	}
	if ($limit) {
	    $sql .= ' LIMIT '.$limit;
	}
	$sql .= ';';
	if (!isset($this->handles[$sql])) {
	    $result = $this->query($sql);
	    $this->handles[$sql] = $result;
	}
	if ($this->handles[$sql])
	    if ($row = $this->fetchAssoc($this->handles[$sql])) {
		$row["_meta_tableName"] = $tableName;
		if ($dontKeepResource) {
		    unset($this->handles[$sql]);
		}
		return $row;
	    } else {
		unset($this->handles[$sql]);
		  return false;
	    }

	unset($this->handles[$sql]);
	return false;
    }

    function getTableColumns ($tableName) {
	$tableName = $this->check($tableName);
	$ret = array();
	$desc = $this->getQueryArray("DESC ".$this->check($tableName));
	foreach ($desc as $col) {
	    $ret[] = $col["Field"];
	}
	return $ret;
    }

    function getQueryArray ($query, $force = false, $dontCache = false) {
	if (isset($this->cache[$query]) && (!$force))
	    return ($this->cache[$query]);

	$ret = array();
	if ($result = $this->query($query))
	    while ($row =  $this->fetchAssoc($result))
		$ret[] = $row;

	if (!$dontCache)
	    $this->cache[$query] = $ret;

	return $ret;
    }

    function save($newMode, &$row, $tableName = NULL, $maxSaveRecurse = 0, $transactional = false) {
	if (isset($tableName)) {
	    $row["_meta_tableName"] = $tableName;
	} else {
	    $tableName = $row["_meta_tableName"];
	}

	    $pairs = array();
	    $last = '';
	    if ($cols = $this->getTableColumns($tableName)) {
		foreach ($cols as $col) {
		    if (isset ($row[$col]))
			$content = $this->check($row[$col]);
			$pairs[] = "`$col` = \"$content\"";
			$content = NULL;
		}
	    }
	    if ($newMode) {
		$sql = 'INSERT INTO '.$tableName.' '.
		    'SET '.implode(", ", $pairs);
	    } else {
		$sql = 'UPDATE '.$tableName.' '.
		    'SET '.implode(", ", $pairs).' '.
		    'WHERE `id` = "'.$row["id"].'"';
	    }
	    $this->query($sql, false, $transactional); // TODO: toto pre recursive nefunguje tak ako by malo

	    if ($newMode && in_array("id", $cols) && (!isset($row["id"])))
		$row["id"] = $this->insertId();
	    $row["_meta_affectedRows"] = $this->affectedRows();
	    if ($this->debug) $row["_meta_SQL"] = $sql;
	    return ($row["_meta_affectedRows"]);
    }

    function destroy($row, $transactional = false) {
	$tableName = $row["_meta_tableName"];
	    $sql = 'DELETE FROM '.$tableName.' WHERE id='.$row["id"];
	    $this->query($sql, false, $transactional);
	return ($this->affectedRows());
    }

    function destroyByCond($tableName, $whereConditions, $transactional = false) {
	foreach ((array)$whereConditions as $cond) {
	    $conditions[] = "($cond)";
	}
	$sql =  'DELETE FROM '.$tableName.' WHERE '.implode(' AND ', $conditions);
	$this->query($sql, false, $transactional);
	return ($this->affectedRows());
    }

    function query($sql, $cache = false, $transactional = false, $multi = false) {
	if ($this->debug == true) {
	    $this->history[] = $sql;
	}
// 	echo $sql."<br />\n";
	$out = false;

	if ($transactional) {
	    $this->db->query("START TRANSACTION;");
	    if ($out = $this->db->query($sql))
		$this->db->_query("COMMIT;");
	    else
		$this->db->query("ROLLBACK;");
	} else if($multi) {
		$out = true;
		$this->db->multi_query($sql);
		
		while($this->db->next_result());
		
		if($this->db->errno)
			$out = false;
	} else {
	    $out = $this->db->query($sql);
	    if($this->db->errno) {
			echo $sql."\n:<br>\n";
			echo $this->db->error."\n<br><br>\n";
			$out = false;
		}
	}

	return $out;
    }

    function clearCache() {
    	unset($cache);
    }

    function fetchRow($handle) {
	return mysqli_fetch_row($handle);
    }

    function fetchArray($handle) {
	return mysqli_fetch_array($handle);
    }

    function fetchAssoc($handle) {
	return mysqli_fetch_assoc($handle);
    }

    function fetchObject($handle) {
	return mysqli_fetch_object($handle);
    }

    function numFields($ofWhat) {
	return mysqli_num_fields($ofWhat);
    }

    function affectedRows() {
	return $this->db->affected_rows;
    }

    function insertId() {
	return $this->db->insert_id;
    }

    function check($string) {
	return $this->db->real_escape_string($string);
    }
    function query_trans($cmd, &$error, $multi = false)
    {
    	$this->query("BEGIN;");
    	
    	if ($this->query($cmd, false, false, $multi)) {
    		$this->query("COMMIT;");
    		return true;
    	} else {
			$error = $this->db->error;
    		$this->query("ROLLBACK;");
    		return false;
    	}
    }

    function fetch_row($handle) {
	return $this->fetchRow($handle);
    }

    function fetch_array($handle) {
	return $this->fetchArray($handle);
    }
    function fetch_object($handle) {
	return $this->fetchObject($handle);
    }

    function num_fields($of_what) {
	return $this->numFields($of_what);
    }

    function affected_rows() {
	return $this->affectedRows();
    }

    function insert_id() {
	return $this->insertId();
    }
    
    function error() {
    return $this->db->error;
    }
    
    function __destruct() {
    	$this->db->close();
    }
    function _disconnect() {
    	return mysql_close($this->connection);
    }
    function _connect() {
      $this->db = mysqli_init();

      @$this->db->real_connect($this->host, $this->user, $this->pass, $this->name);

	if ($this->db->connect_errno)
		die ('Unable to connect to the database. Error: '.$this->db->errno.' '.$this->db->error);

	return true;
    }

};

/*class sql_db
  {
    public $connection;
    private $host;
    private $user;
    private $pass;
    private $name;

    function sql_db($host,$user,$pass,$name)
    {
    	$this->host = $host;
    	$this->user = $user;
    	$this->pass = $pass;
    	$this->name = $name;

	return $this->_connect();
    }

    function query($cmd)
    {

  //   if (DEBUG)
    //  array_push($_SESSION["db_queries"], $cmd);
    return mysql_query($cmd,$this->connection);
    }

    function query_trans($cmd)
    {
    	$this->query("BEGIN;");

    	if ($this->query($cmd)) {
    		$this->query("COMMIT;");
    		return true;
    	} else {
    		$this->query("ROLLBACK;");
    		return false;
    	}
    }

    function fetch_row($handle)
    {
    return mysql_fetch_row($handle);
    }

    function fetch_array($handle)
    {
    return mysql_fetch_array($handle);
    }
    function fetchArray($handle) {
    	return $this->fetch_array($handle);
    }

    function fetch_object($handle)
    {
    return mysql_fetch_object($handle);
    }

    function num_fields($of_what)
    {
    return mysql_num_fields($of_what);
    }

    function affected_rows()
    {
    return mysql_affected_rows();
    }

	function insert_id() {
		return mysql_insert_id();
	}

	function check($string) {
		return mysql_real_escape_string($string);
	}
  };*/

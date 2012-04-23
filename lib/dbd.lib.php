<?php

class sql_db
  {
    public $connection;
    private $host;
    private $user;
    private $pass;
    private $name;
	private $handles;

    function sql_db($host,$user,$pass,$name)
    {
    	$this->host = $host;
    	$this->user = $user;
    	$this->pass = $pass;
    	$this->name = $name;

	return $this->_connect();
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

    function find ($tableName, $whereConditions = NULL, $ordering = NULL, $limit = NULL, $maxRecurse = 1, $dontKeepResource = false) {
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
    function _disconnect() {
        return mysql_close($this->connection);
    }
    function _connect() {
        $this->connection = mysql_connect($this->host,$this->user,$this->pass);

    if (!$this->connection) {
        echo ('Unable to connect to database.');
        exit;
    }

    if (!mysql_select_db($this->name,$this->connection)) {
        echo ('Unable to connect to database.');
        exit;
    }

    $_SESSION["db_queries"] = array();
    return $this->connection;
    }

  };
?>

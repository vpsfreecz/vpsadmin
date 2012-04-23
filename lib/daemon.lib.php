<?php
abstract class Daemon {
	public $pidfile = "/var/run/program.pid";
	public $mypid;

	abstract protected function worker();

	function __construct($program) {
		$this->pidfile = "/var/run/{$program}.pid";

		declare (ticks=1);

		if ($this->checkPidFile())
			die("Pid File: ".$this->pidfile." already exists\n");

		$this->_fork();
		$this->_createPidFile();

		pcntl_signal(SIGTERM, array(&$this, "handleSIG"));
		pcntl_signal(SIGHUP,  array(&$this, "handleSIG"));

		$this->beforeDaemon();

		while (1) {
			$this->worker();
		}
	}

	public function checkPidFile() {
		if (($fp = @fopen($this->pidfile, "r"))===false)
			return false;

		return fread($fp, filesize($this->pidfile));
	}

	public function handleSIG($signo) {
		switch ($signo) {
			case SIGTERM:
				$this->_removePidFile();
				exit();
			break;
			default:

			break;
		}
	}

	protected function beforeDaemon() {

	}

	private function _fork() {
		$pid = pcntl_fork();
		if ($pid == -1) {
			die("Could not fork\n");
		} elseif ($pid) {
			exit();
		}

		$sid = posix_setsid();
		if ($sid == -1)
			die("Could not detach from terminal\n");

		$this->mypid = posix_getpid();
	}

	private function _createPidFile() {


		$fp = @fopen($this->pidfile, "w");
		fwrite($fp, $this->mypid);
		fclose($fp);
	}

	private function _removePidFile() {
		return unlink ($this->pidfile);
	}
}


class vpsAdmin extends Daemon {
	private $sql = "SELECT UNIX_TIMESTAMP(UPDATE_TIME) as time FROM `information_schema`.`tables`  WHERE  `TABLE_SCHEMA` =  'vpsadmin' AND  `TABLE_NAME` =  'transactions';";
	private $old_time = 0;

	function __construct () {
		parent::__construct("vpsadmin");
	}

	public function worker() {
		global $db;

		$this->db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

		if (!($r = $this->db->query($this->sql))) {
			$this->db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);
			sleep(30);
		} else {
			$result = $this->db->fetch_array($r);

			if ($result['time'] > $this->old_time) {
				$db = $this->db;
				do_all_transactions_by_server(SERVER_ID);
				update_all_vps_status();
				$this->old_time = $result['time'];
			}

			sleep (1);
		}
	}
}

?>
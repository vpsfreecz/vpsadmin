<?php
/*
    ./lib/firewall.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net
    Copyright (C) 2009 Frantisek Kucera, franta@vpsfree.cz

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
 * Knihovna pro správu uživatelských firewallů.
 */

class FirewallRule {
    var $id;
    var $ipVersion;
    var $command;
    var $approved;

    function FirewallRule ($id, $ipVersion, $command, $approved) {
	$this->id = $id;
	$this->ipVersion = $ipVersion;
	$this->command = $command;
	$this->approved = $approved;
    }
}

class FirewallIP {
    var $ipId;
    var $ipAddr;
    var $hostname;
    var $memberNick;

    function FirewallIP($ipId, $ipAddr, $hostname, $memberNick) {
	$this->ipId = $ipId;
	$this->ipAddr = $ipAddr;
	$this->hostname = $hostname;
	$this->memberNick = $memberNick;
    }

}

/**
 * Pro práci s databází
 */
class FirewallDAO {

    var $db;

    /**
     * @param <type> $database databázové spojení, pravděpodobně $GLOBALS["db"]
     */
    function FirewallDAO ($database) {
	$this->db = $database;
    }

    function getIPs($admin, $memberId) {
	if ($admin) {
	    $sql = "SELECT  ip_id,
                            ip_addr,
                            vps_hostname,
                            m_id,
			    m_nick
                    FROM    vps_ip
                    JOIN    vps USING (vps_id)
                    JOIN    members USING (m_id)
		    ORDER BY m_nick;";
	} else {
	    $sql = "SELECT  ip_id,
                            ip_addr,
                            vps_hostname,
                            m_id,
			    m_nick
                    FROM    vps_ip
                    JOIN    vps USING (vps_id)
                    JOIN    members USING (m_id)
                    WHERE   m_id = " . $this->db->check($memberId) . "
		    ORDER BY m_nick;";
	/** TODO: přepsat db.lib.php, aby se používaly parametrizovaníé dotazy (proti SQL injection) */
	}



	if ($result = $this->db->query($sql)) {
	    $ret = array();
	    while ($row = $this->db->fetch_array($result)) {
		$ret[] = new FirewallIP($row["ip_id"], $row["ip_addr"], $row["vps_hostname"], $row["m_nick"]);
	    }
	    return $ret;
	} else {
	    return false;
	}


    }

    /**
     * Zda má uživatel práva k dané IP adrese
     * @param boolean $admin – admin má práva ke všemu
     * @param int $ipId – ID IP adresy
     * @param int $memberId – ID člena
     */
    function checkRights($admin, $ipId, $memberId) {
	if ($admin) {
	    return true;
	} else {
	    $sql = "SELECT  count(*) AS count
		    FROM    vps_ip
		    JOIN    vps USING (vps_id)
		    WHERE   ip_id = " . $this->db->check($ipId) . "
			    AND m_id = " . $this->db->check($memberId) . ";";

	    if ($result = $this->db->query($sql)) {
		$row = $this->db->fetch_array($result);
		return $row["count"] == 1;
	    } else {
		return false;
	    }
	}
    }

    function getRules($ipId) {
	$sql = "SELECT	id,
			ip_v,
			command,
			approved
		FROM	firewall f
		JOIN	vps_ip ip ON (f.ip = ip.ip_id)
		WHERE	ip = " . $this->db->check($ipId) . "
		ORDER BY ordinal;";

	if ($result = $this->db->query($sql)) {
	    $ret = array();
	    while ($row = $this->db->fetch_array($result)) {
		$ret[] = new FirewallRule($row["id"], $row["ip_v"], $row["command"], $row["approved"]);
	    }
	    return $ret;
	} else {
	    return false;
	}
    }

    /**
     * Vrací pravidla připravená k nasazení.
     * Musí být platná všechna, jinak se neaplikuje nic.
     * Příkazy jsou upravené: místo INPUT a OUTPUT obsahují INPUT_x a OUTPUT_x, kde x je id IP adresy.
     * @param int $ipId – id IP adresy
     * @return array pole pravidel (FirewallRule) dané ip adresy,
     * nebo false, pokud některé z pravidel nebylo schváleno
     * Pověsit Frantu za uši do průvanu a nechat viset aspoň tejden za $rule->command (objektovej přístup všude kde se to nehodí :-D)
     */
    function getCheckedRules($ipId) {
	$rules = $this->getRules($ipId);
	foreach ($rules as $rule) {
	    $rule->command = $this->rewriteTableInCommand($rule->command, $ipId);
	    if (!$rule->approved) {
		return false;
	    }
	    $ret[rules][] = $rule->command;
	}
	if (count($rules) < 1) return false;
	$ip = get_ip_by_id($ipId);
	$ret[ip_v] = $ip[ip_v];
	$ret[ip_id] = $ip[ip_id];
	return $ret;
    }
    function rewriteTableInCommand($command, $ipId) {
	/** TODO: přepisovat */
	$command = preg_replace("/INPUT/", "INPUT_$ipId", $command);
	$command = preg_replace("/OUTPUT/", "OUTPUT_$ipId", $command);
	return $command;
    }

    /**
     * Uloží pravidla do databáze.
     * @param array $rules pole pravidel (textů)
     * @param int $ipId id IP adresy
     */
    function saveRules($rules, $ipId) {
	$sqlDelete = "DELETE FROM firewall WHERE ip = " . $this->db->check($ipId);
	$this->db->query($sqlDelete);
	$ordinal = 0;
	foreach ($rules as $rule) {
	    if (strlen($rule) > 0) {
		$ordinal++;
		$sqlInsert = "INSERT INTO firewall (ip, command, ordinal, approved)
			      VALUES (" . $this->db->check($ipId) . ", '" . $this->db->check($rule) . "', $ordinal, false);";
		$this->db->query($sqlInsert);
	    }
	}
    }

    /**
     * Zkontroluje pravidla dané IP adresy a nastaví u nich příznak „approved“
     * @param int $ipId id IP adresy
     */
    function checkRules($ipId) {
	$rules = $this->getRules($ipId);
	foreach ($rules as $rule) {
	    $approved = $this->checkRule($rule);
	    $sql = "UPDATE firewall
		    SET command = '" . $this->db->check($rule->command) . "', approved = " . $this->db->check($approved) . "
		    WHERE id = " . $this->db->check($rule->id);
	    $this->db->query($sql);
	}
    }

    /**
     * Kontroluje pravidlo iptables jestli odpovídá některému z vzorů
     * @param FirewallRule $rule – pravidlo iptables
     * @return boolean – schváleno nebo neschváleno
     */
    function checkRule(FirewallRule $rule) {
	$validPatterns4 = array();
	$validPatterns6 = array();

	$ipv4Pattern = "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)";
	$ipv6Pattern = "[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}";

	/** Vybrané porty povolíme, zahodíme nebo odmítneme. */
	$validPatterns4[] = "/^-A INPUT -p (tcp|udp) --dport [0-9]+ -j (ACCEPT|REJECT|DROP)$/";
	$validPatterns6[] = "/^-A INPUT -p (tcp|udp) --dport [0-9]+ -j (ACCEPT|REJECT|DROP)$/";

	/** Vybraný port a vybraná IP adresa → povolit/odmítnout/zahodit */
	$validPatterns4[] = "/^-A INPUT -p (tcp|udp) -s $ipv4Pattern --dport [0-9]+ -j (ACCEPT|REJECT|DROP)$/";
	$validPatterns6[] = "/^-A INPUT -p (tcp|udp) -s $ipv6Pattern --dport [0-9]+ -j (ACCEPT|REJECT|DROP)$/";

	/** Ping */
	$validPatterns4[] = "/^-A INPUT -p icmp -m icmp --icmp-type 8 -j (ACCEPT|REJECT|DROP)$/";
	$validPatterns6[] = "/^-A INPUT -p ipv6-icmp -j (ACCEPT|REJECT|DROP)$/";

	/** Navázaná spojení */
	$validPatterns4[] = "/^-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT$/";
	$validPatterns6[] = "/^-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT$/";

	/** Zbytek zahodit nebo odmítnout. */
	$validPatterns4[] = "/^-A INPUT -j (DROP|REJECT)$/";
	$validPatterns6[] = "/^-A INPUT -j (DROP|REJECT)$/";

	if ($rule->ipVersion == 4) {
	    foreach ($validPatterns4 as $pattern) {
		if (preg_match($pattern, $rule->command) == 1) {
		    /** Vyhovuje alespoň jednomu pravidlu → schválíme. */
		    return true;
		}
	    }
	}

	if ($rule->ipVersion == 6) {
	    foreach ($validPatterns6 as $pattern) {
		if (preg_match($pattern, $rule->command) == 1) {
		    /** Vyhovuje alespoň jednomu pravidlu → schválíme. */
		    return true;
		}
	    }
	}

	/** Nevyhovuje ani jednomu pravidlu → zamítneme. */
	return false;
    }

    function hasUnapprovedRules($ipId) {
	$sql = 'SELECT COUNT(*) as count FROM firewall WHERE ip = '.$this->db->check($ipId).' AND approved = 0';
	$result = $this->db->query($sql);
	$row = $this->db->fetch_array($result);
	return ($row["count"] > 0);
    }
}

?>
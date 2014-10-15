<?php
session_start();

include '/etc/vpsadmin/config.php';
include WWW_ROOT.'lib/version.lib.php';

header('Content-Type: text/javascript');

if($_SESSION['logged_in']) {
?>
(function(root) {
root.vpsAdmin = {
	api: {
		url: "<?php echo API_URL ?>",
		version: "<?php echo API_VERSION ?>"
	},
	authToken: "<?php echo $_SESSION['auth_token'] ?>",
	description: <?php echo json_encode($_SESSION['api_description']) ?>
};

function chainIcon(state) {
	var img = $("<img>");
	var src;
	
	switch (state) {
		case 'staged':
		case 'queued':
			src = "transact_pending.gif";
			break;
			
		case "done":
			src = "transact_ok.png";
			break;
			
		case 'failed':
			src = "transact_fail.png";
			break;
			
		default:
			src = "transact_fail.png";
			break;
	}
	
	return img.attr('src', 'template/icons/' + src);
}

function createChainRow(chain) {
	var tr = $("<tr>")
		.attr('data-transaction-chain-id', chain.id)
		.attr('data-transaction-chain-progress', chain.progress)
		.addClass(chain.state);
	
	tr.append($("<td>").text( chain.id ));
	tr.append($("<td>").text( chain.label ));
	tr.append($("<td>").attr('align', 'right').text( chain.progress + ' %' ));
	tr.append($("<td>").append( chainIcon(chain.state) ));
	
	tr.hide();
	
	return tr;
}

function addChains(chains, num) {
	var table = $("#transactions table");
	
	for(var i = num - 1; i >= 0; i--) {
		var row = createChainRow(chains.itemAt(i));
		
		table.find("th").parent().after(row);
		row.fadeIn("slow");
	}
}

function checkChanges(chains, from) {
	var i = from;
	
	$("#transactions table tr:has(td)").slice(-1 * (10 - from)).each(function() {
		var chain = chains.itemAt(i);
		
		//console.log("checking row", i, this.getAttribute('data-transaction-chain-id'), chain.id);
		
		if (this.getAttribute('data-transaction-chain-progress') != chain.progress) {
			this.setAttribute('data-transaction-chain-progress', chain.progress);
			$(this).removeClass().addClass(chain.state);
			
			$(this).find("td:nth-child(3)").text( ((100.0 / chains.itemAt(i).size) * chain.progress) + ' %' );
			$(this).find("td:nth-child(4) img").replaceWith( chainIcon(chain.state) );
		}
		
		i += 1;
	});
}

function updateChains(api) {
	api.transaction_chain.list({limit: 10}, function(c, chains) {
		if (chains.length == 0)
			return;
		
		var last = chains.last();
		var count = 0;
		var removeNum = $("#transactions table tr:has(td)").length;
		
		$("#transactions table tr:has(td)").each(function() {
			removeNum -= 1;
			count += 1;
			
			if (this.getAttribute("data-transaction-chain-id") == last.id) {
				//console.log("found common chain", last.id);
				return false;
			}
		});
		
		if (removeNum > 0) {
			//console.log("will remove", removeNum, "elements");
			
			$("#transactions table tr").slice(-1 * removeNum).fadeOut(500, function() {
				this.remove();
			});
			
			setTimeout(function() {
				addChains(chains, removeNum);
				checkChanges(chains, removeNum);
				
			}, 500);
			
		} else if (chains.length < 10 && removeNum == 0 && count > 0) {
			addChains(chains, chains.length - count);
			checkChanges(chains, 0);
			
		} else {
			checkChanges(chains, 0);
		}
		
		//return;
		setTimeout(function() {
			updateChains(api);
		}, 1000);
	});
}

var api = new HaveAPI.Client(root.vpsAdmin.api.url, {version: root.vpsAdmin.api.version});
api.useDescription(root.vpsAdmin.description);
api.authenticate('token', {token: root.vpsAdmin.authToken}, function(api) {
	
	setTimeout(function() {
		updateChains(api);
	}, 1000);
	
}, false);

})(window);
<?php } ?>

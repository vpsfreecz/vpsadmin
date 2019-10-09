(function() {
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

	function chainConcernLink(obj) {
		switch (obj[0]) {
			case 'Vps':
				return '<a href="?page=adminvps&action=info&veid='+ obj[1] +'">'+ obj[1] +'</a>';

			case 'User':
				return '<a href="?page=adminm&action=edit&id='+ obj[1] +'">'+ obj[1] +'</a>';

			case 'UserPayment':
				return '<a href="?page=redirect&to=payset&from=payment&id='+ obj[1] +'">'+ obj[1] +'</a>';

			case 'RegistrationRequest':
				return '<a href="?page=adminm&action=request_details&id='+ obj[1] +'&type=registration">'+ obj[1] +'</a>';

			case 'ChangeRequest':
				return '<a href="?page=adminm&action=request_details&id='+ obj[1] +'&type=change">'+ obj[1] +'</a>';

			case 'Outage':
				return '<a href="?page=outage&action=show&id='+ obj[1] +'">'+ obj[1] +'</a>';

			case 'Export':
				return '<a href="?page=export&action=edit&export='+ obj[1] +'">'+ obj[1] +'</a>';

			default:
				return obj[1];
		}
	}

	function chainConcernClass(obj) {
		var klassMap = {
			Vps: 'VPS'
		};

		if (klassMap[obj[0]])
			return klassMap[obj[0]];

		return obj[0];
	}

	function chainConcerns(chain) {
		if (!chain.concerns)
			return '---';

		switch (chain.concerns.type) {
			case 'affect':
				return chainConcernClass(chain.concerns.objects[0]) + ' ' + chainConcernLink(chain.concerns.objects[0]);

			case 'transform':
				src = chain.concerns.objects[0];
				dst = chain.concerns.objects[1];

				return chainConcernClass(src) + ' ' + chainConcernLink(src) + ' -> ' + chainConcernLink(dst);

			default:
				return 'Unknown';
		}
	}

	function createChainRow(chain) {
		var tr = $("<tr>")
			.attr('data-transaction-chain-id', chain.id)
			.attr('data-transaction-chain-progress', chain.progress)
			.addClass(chain.state);

		tr.append($("<td>").html( "<a href=\"?page=transactions&chain="+ chain.id +"\">"+ chain.id +"</a>" ));
		tr.append($("<td>").html(chainConcerns(chain)));
		tr.append($("<td>").text( chain.label ));
		tr.append($("<td>").attr('align', 'right').text( Math.round((100.0 / chain.size) * chain.progress) + ' %' ));
		tr.append($("<td>").append( chainIcon(chain.state) ));

		tr.hide();

		return tr;
	}

	function addChains(chains, num) {
		var table = $("#transactions table");

		for(var i = num - 1; i >= 0; i--) {
			var row = createChainRow(chains.itemAt(i));

			table.find("th").parent().after(row);
			row.fadeIn({
				duration: "slow",
				start: function(){ this.style.display = 'table-row'; }
			});
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

				$(this).find("td:nth-child(4)").text( Math.round((100.0 / chain.size) * chain.progress) + ' %' );
				$(this).find("td:nth-child(5) img").replaceWith( chainIcon(chain.state) );
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
			chainTimeout = setTimeout(function() {
				updateChains(api);
			}, 3000);
		});
	}

	api.after('authenticated', function() {
		chainTimeout = setTimeout(function() {
			updateChains(api);
		}, 1000);
	});
})();

function showGoresheatWindow(rootUrl, serverUrl, serverName) {
	// Create the goresheat window div
	var goresheatWindow = document.createElement('div');
	goresheatWindow.className = 'goresheat-window';
	goresheatWindow.id = 'goresheatWindow';

	// Create the header div
	var header = document.createElement('div');
	header.className = 'header';

	// Create the window title
	var title = document.createElement('div');
	title.className = 'window-title';
	title.innerHTML = '<a href="' + rootUrl + '">Root</a> &raquo; <a href="' + serverUrl + '">' + serverName + '</a>: CPU user, system, idle; disk I/O';
	header.appendChild(title);

	// Create the close button
	var closeBtn = document.createElement('div');
	closeBtn.className = 'close-btn';
	closeBtn.innerHTML = '<a href="#" onclick="closeGoresheatWindow(event)">Close</a>';
	header.appendChild(closeBtn);

	goresheatWindow.appendChild(header);

	// Create the iframe
	var iframe = document.createElement('iframe');
	iframe.id = 'resourceFrame';
	iframe.src = serverUrl;
	goresheatWindow.appendChild(iframe);

	// Append the goresheat window to the body
	document.body.appendChild(goresheatWindow);

	// Configure the overlay to close the window on click
	var overlay = document.getElementById('overlay');
	overlay.onclick = closeGoresheatWindow;

	// Display the overlay and the goresheat window
	overlay.style.display = 'block';
	goresheatWindow.style.display = 'block';
}

function closeGoresheatWindow(event) {
	// Prevent the event from propagating to the overlay click handler
	if (event) event.stopPropagation();

	// Find the goresheat window and remove it
	var goresheatWindow = document.getElementById('goresheatWindow');
	if (goresheatWindow) {
			document.body.removeChild(goresheatWindow);
	}

	// Hide the overlay and unset the onclick action
	var overlay = document.getElementById('overlay');
	overlay.style.display = 'none';
	overlay.onclick = null;
}

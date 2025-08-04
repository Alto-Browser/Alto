(function() {
  function findAllMediaAndLinks(el) {
	var found = {
	  link: null,
	  image: null,
	  video: null,
	  text: null
	};

	while (el) {
	  if (el.nodeType === Node.TEXT_NODE) {
		el = el.parentElement;
		continue;
	  }

	  if (!found.link && el.tagName === "A") {
		found.link = el;
	  }

	  if (!found.image && el.tagName === "IMG") {
		found.image = el;
	  }

	  if (!found.video && el.tagName === "VIDEO") {
		found.video = el;
	  }

	  if (
		!found.text &&
		el.children.length === 0 &&
		el.textContent &&
		el.textContent.trim().length > 0
	  ) {
		found.text = el;
	  }

	  if (found.link && found.image && found.video) break;

	  el = el.parentElement;
	}

	return found;
  }

  window.addEventListener("contextmenu", function(event) {
	event.preventDefault();

	var found = findAllMediaAndLinks(event.target);
	var selection = window.getSelection();
	var selectedText = selection ? selection.toString().trim() : "";

	var message = null;

	var isSelectionInside =
	  selectedText.length > 0 &&
	  found.text &&
	  selection &&
	  selection.anchorNode &&
	  found.text.contains(selection.anchorNode);

	if (isSelectionInside) {
	  if (found.link) {
		message = {
		  type: "link",
		  value: found.link.href,
		  containsImage: !!found.image
		};
	  } else {
		message = {
		  type: "text",
		  value: selectedText
		};
	  }
	} else if (found.link) {
	  message = {
		type: "link",
		value: found.link.href,
		containsImage: !!found.image
	  };
	} else if (found.image) {
	  message = {
		type: "image",
		value: found.image.src
	  };
	} else if (found.video) {
	  var videoSrc = found.video.src || (found.video.querySelector('source') && found.video.querySelector('source').src) || null;
	  message = {
		type: "video",
		value: videoSrc || "no-src"
	  };
	} else if (found.text) {
	  message = {
		type: "text",
		value: found.text.textContent.trim()
	  };
	} else {
	  message = {
		type: "unknown",
		value: ""
	  };
	}


	if (window.webkit?.messageHandlers?.menuHandler) {
		window.webkit.messageHandlers.menuHandler.postMessage(message);
	  } else {
		console.log("Handler not found", message);
	}

	return false;
  });
})();


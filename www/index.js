import * as wasm from "electric-fields-with-rust";
import "./elm.js"

//////////////////////////////////////////// elm ///////////////////////////////////////
var localStorageKey = "electric-fields-simulation";

// load saved project from localStorage
var savedProject = localStorage.getItem(localStorageKey);

// initiate elm app
var app = Elm.Main.init({ node: document.querySelector('main'), flags: savedProject });

// download model as svg
app.ports.downloadModelAsSvg.subscribe(function(modelName) {
  var activeSource = document.getElementById("activeSource");
  if (activeSource !== null) {
    var strokeWidth = activeSource.getAttribute("stroke-width");
    activeSource.setAttribute("stroke-width", "0px");
  }
  var sourceValueLabel = document.getElementById("sourceValueLabel");
  if (sourceValueLabel !== null) {
    sourceValueLabel.setAttribute("visibility", "hidden");
  }
  var svgData = document.getElementById("modelSvg")
    .outerHTML
    .replace(/^<svg/, `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"`);
  if (activeSource !== null) {
    activeSource.setAttribute("stroke-width", strokeWidth);
  }
  if (sourceValueLabel !== null) {
    sourceValueLabel.setAttribute("visibility", "visible");
  }
  download(modelName + ".svg", "image/svg+xml;charset=utf-8", svgData);
});

function download(fileName, type, data) {
  var blob = new Blob([data], {type: type});
  var url = URL.createObjectURL(blob);
  var downloadLink = document.createElement("a");
  downloadLink.href = url;
  downloadLink.download = fileName;
  document.body.appendChild(downloadLink);
  downloadLink.style.display = 'none';
  downloadLink.click();
  document.body.removeChild(downloadLink);
}

// save project
app.ports.saveProject.subscribe(function(project) {
  var projectJson = JSON.stringify(project);
  localStorage.setItem(localStorageKey, projectJson);
});

// calculate fields
app.ports.calculateFieldsPort.subscribe(function([width, height, fields_in_json]) {
  app.ports.receiveFieldsPort.send(wasm.calculate_fields(width, height, fields_in_json));
});

window.addEventListener("beforeunload", function() {
  app.ports.pageWillClose.send(null);
});


////////////////////////////////////// service worker //////////////////////////
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').then(registration => {
      console.log('SW registered: ', registration);
    }).catch(registrationError => {
      console.log('SW registration failed: ', registrationError);
    });
  });
}

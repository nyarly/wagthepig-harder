import { Elm } from "../elm/Main.elm";
import { allState, addLocalStoragePorts } from "./ports/localstorage.js";

var flags = allState();

var app = Elm.Main.init({
  node: document.getElementById('myapp'),
  flags: flags
});
addLocalStoragePorts(app);

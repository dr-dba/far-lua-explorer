Originally from @JD Lua Explorer „Advanced“
<br />
https://gist.github.com/johnd0e/5110ddfb3291928a7f484cd38f23ff87/
<br />
Discussion page of @JD version:
<br />
https://forum.farmanager.com/viewtopic.php?f=60&t=7988
<br />
"Lua Explorer @Xer0X" version and discussion page:
<br />
https://github.com/dr-dba/far-lua-explorer/
<br />
https://forum.farmanager.com/viewtopic.php?f=15&t=12374
<br />
changes are:
* Retentive, i.e. reopened on the same object (=table) subelement
* Ability to navigate by the given path, <br />
for example this:<br />
lua`:LE(_G, nil, nil, nil, { "Area" })`<br />
.. will open the `"[ _G ==>> Area ]" table<br />
and this:<br />
lua: `LE(_G, nil, nil, nil, { "far", "Colors" })`<br />
.. will open the `[ _G ==>> far ==>> Colors ]` table<br />
* Not like in original code exiting on Escape, <br />
this modification exits on Escape, goes back on BackSpace<br />
* Custom sorts can be defined
* Certain fields (properties) can be hidden

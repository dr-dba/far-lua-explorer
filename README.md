Originally from @JD:
<br />
https://gist.github.com/johnd0e/5110ddfb3291928a7f484cd38f23ff87/
<br />
https://forum.farmanager.com/viewtopic.php?t=7988
<br />
.. with my and @Xer0X's changes

changes are:
* Retentive, i.e. reopened on the same object (=table) subelement
* Ability to navigate by given path, <br />
for example this:<br />
lua`:LE(_G, nil, nil, nil, {"Area"})`<br />
.. will open the `"_G=>Area`" table<br />
and this:<br />
lua: `LE(_G, nil, nil, nil, {"far", "Colors"})`<br />
.. will open the `{_G=>far=>Colors}` table<br />
* Not like in original code exiting on Escape, <br />
this modification exits on Escape, goes back on BackSpace<br />

